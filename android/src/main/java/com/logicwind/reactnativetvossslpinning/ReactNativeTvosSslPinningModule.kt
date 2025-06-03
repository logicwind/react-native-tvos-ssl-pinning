package com.logicwind.reactnativetvossslpinning

import com.facebook.react.bridge.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.security.cert.CertificateException
import javax.net.ssl.*
import java.security.KeyStore
import java.security.cert.Certificate
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.io.ByteArrayInputStream
import java.util.concurrent.TimeUnit
import javax.net.ssl.TrustManagerFactory
import java.io.InputStream

class ReactNativeTvosSslPinningModule(reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String {
    return NAME
  }

  override fun getName(): String {
        return "SSLPinning"
  }

  @ReactMethod
  fun fetch(url: String, obj: ReadableMap, promise: Promise) {
      fetchDataWithPinning(url, obj, promise)
  }

  @ReactMethod
  fun fetchDataWithPinning(url: String, obj: ReadableMap, promise: Promise) {
      try {
          // Extract certificate names from options
          val certNames = extractCertNames(obj)
          
          // Create OkHttpClient with specified certificates
          val client = createOkHttpClient(certNames)
          val request = createRequest(url, obj)
          
          // Set timeout from options
          val timeout = if (obj.hasKey("timeoutInterval")) {
              obj.getInt("timeoutInterval").toLong()
          } else {
              30000L // Default 30 seconds
          }
          
          val clientWithTimeout = client.newBuilder()
              .connectTimeout(timeout, TimeUnit.MILLISECONDS)
              .readTimeout(timeout, TimeUnit.MILLISECONDS)
              .writeTimeout(timeout, TimeUnit.MILLISECONDS)
              .build()
          
          clientWithTimeout.newCall(request).enqueue(object : okhttp3.Callback {
              override fun onFailure(call: Call, e: IOException) {
                  promise.reject("NETWORK_ERROR", e.message, e)
              }

              override fun onResponse(call: Call, response: Response) {
                  try {
                      val responseBody = response.body?.string() ?: ""
                      val responseMap = Arguments.createMap().apply {
                          putInt("status", response.code)
                          putString("data", responseBody)
                          putMap("headers", convertHeadersToMap(response.headers))
                      }
                      promise.resolve(responseMap)
                  } catch (e: Exception) {
                      promise.reject("RESPONSE_ERROR", e.message, e)
                  } finally {
                      response.close()
                  }
              }
          })
      } catch (e: Exception) {
          promise.reject("REQUEST_ERROR", e.message, e)
      }
  }

  private fun extractCertNames(obj: ReadableMap): List<String> {
      return try {
          if (obj.hasKey("sslPinning")) {
              val sslPinning = obj.getMap("sslPinning")
              if (sslPinning?.hasKey("certs") == true) {
                  val certsArray = sslPinning.getArray("certs")
                  val certNames = mutableListOf<String>()
                  
                  for (i in 0 until (certsArray?.size() ?: 0)) {
                      certsArray?.getString(i)?.let { certName ->
                          // Check if the name already has an extension
                          val finalCertName = if (certName.contains('.')) {
                              certName // Use as-is if it already has an extension
                          } else {
                              // Try common certificate extensions
                              val possibleExtensions = listOf(".cer", ".crt", ".pem")
                              var foundCert: String? = null
                              
                              for (ext in possibleExtensions) {
                                  val testName = "$certName$ext"
                                  try {
                                      reactApplicationContext.assets.open(testName).close()
                                      foundCert = testName
                                      break
                                  } catch (e: Exception) {
                                      // File doesn't exist, try next extension
                                  }
                              }
                              
                              foundCert ?: "$certName.cer" // Default to .cer if nothing found
                          }
                          certNames.add(finalCertName)
                      }
                  }
                  
                  android.util.Log.d("SSLPinning", "Using certificates: $certNames")
                  certNames
              } else {
                  emptyList()
              }
          } else {
              emptyList()
          }
      } catch (e: Exception) {
          android.util.Log.e("SSLPinning", "Error extracting cert names: ${e.message}")
          emptyList()
      }
  }


  private fun createOkHttpClient(certNames: List<String>): OkHttpClient {
      val builder = OkHttpClient.Builder()

      try {
          if (certNames.isNotEmpty()) {
              // Create custom trust manager with specified certificates
              val trustManager = createTrustManagerWithSpecificCerts(certNames)
              val sslContext = SSLContext.getInstance("TLS")
              sslContext.init(null, arrayOf(trustManager), null)
              
              builder.sslSocketFactory(sslContext.socketFactory, trustManager)
              
              // Custom hostname verifier (accepts all hostnames when using custom certs)
              builder.hostnameVerifier { _, _ -> true }
              
              android.util.Log.d("SSLPinning", "SSL pinning enabled with certificates: $certNames")
          } else {
              android.util.Log.d("SSLPinning", "No SSL pinning certificates specified, using default")
          }
          
      } catch (e: Exception) {
          e.printStackTrace()
          throw SecurityException("Failed to setup SSL pinning: ${e.message}")
      }

      return builder.build()
  }

  private fun createTrustManagerWithSpecificCerts(certNames: List<String>): X509TrustManager {
      // Load only the specified certificates from assets
      val pinnedCertificates = loadSpecificCertificatesFromAssets(certNames)
      
      if (pinnedCertificates.isEmpty()) {
          throw SecurityException("No valid certificates found for names: $certNames")
      }
      
      // Create KeyStore with only the specified pinned certificates
      val keyStore = KeyStore.getInstance(KeyStore.getDefaultType())
      keyStore.load(null, null)
      
      pinnedCertificates.forEachIndexed { index, certificate ->
          keyStore.setCertificateEntry("cert_$index", certificate)
      }

      // Create TrustManager with our KeyStore
      val trustManagerFactory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
      trustManagerFactory.init(keyStore)
      
      val trustManagers = trustManagerFactory.trustManagers
      return trustManagers.first { it is X509TrustManager } as X509TrustManager
  }

  private fun loadSpecificCertificatesFromAssets(certNames: List<String>): List<X509Certificate> {
      val certificates = mutableListOf<X509Certificate>()
      
      try {
          val certificateFactory = CertificateFactory.getInstance("X.509")
          
          for (certFile in certNames) {
              try {
                  val inputStream = reactApplicationContext.assets.open(certFile)
                  val certificate = certificateFactory.generateCertificate(inputStream) as X509Certificate
                  certificates.add(certificate)
                  inputStream.close()
                  
                  // Log certificate info for debugging
                  android.util.Log.d("SSLPinning", "Loaded certificate: $certFile - ${certificate.subjectDN}")
                  
              } catch (e: Exception) {
                  // Certificate file not found or invalid
                  android.util.Log.e("SSLPinning", "Could not load certificate $certFile: ${e.message}")
                  throw SecurityException("Certificate file not found: $certFile")
              }
          }
          
      } catch (e: Exception) {
          e.printStackTrace()
          throw SecurityException("Failed to load certificates: ${e.message}")
      }
      
      return certificates
  }

  private fun createRequest(url: String, obj: ReadableMap): Request {
      val builder = Request.Builder().url(url)

      // Add headers
      if (obj.hasKey("headers")) {
          val headers = obj.getMap("headers")
          headers?.let { headerMap ->
              val iterator = headerMap.keySetIterator()
              while (iterator.hasNextKey()) {
                  val key = iterator.nextKey()
                  val value = headerMap.getString(key)
                  if (value != null) {
                      builder.addHeader(key, value)
                  }
              }
          }
      }

      // Add method and body
      val method = if (obj.hasKey("method")) obj.getString("method") ?: "GET" else "GET"
      
      when (method.uppercase()) {
          "POST", "PUT", "PATCH" -> {
              val body = if (obj.hasKey("body")) {
                  val bodyContent = obj.getString("body") ?: ""
                  val contentType = getContentType(obj)
                  bodyContent.toRequestBody(contentType.toMediaType())
              } else {
                  "".toRequestBody("text/plain".toMediaType())
              }
              builder.method(method, body)
          }
          "DELETE" -> {
              val body = if (obj.hasKey("body")) {
                  val bodyContent = obj.getString("body") ?: ""
                  val contentType = getContentType(obj)
                  bodyContent.toRequestBody(contentType.toMediaType())
              } else {
                  null
              }
              builder.method(method, body)
          }
          else -> builder.method(method, null)
      }

      return builder.build()
  }

  private fun getContentType(obj: ReadableMap): String {
      return if (obj.hasKey("headers")) {
          val headers = obj.getMap("headers")
          headers?.getString("Content-Type") ?: "application/json"
      } else {
          "application/json"
      }
  }

  private fun convertHeadersToMap(headers: Headers): ReadableMap {
      val map = Arguments.createMap()
      for (i in 0 until headers.size) {
          map.putString(headers.name(i), headers.value(i))
      }
      return map
  }

  // Helper method to list available certificates in assets
  @ReactMethod
  fun getAvailableCertificates(promise: Promise) {
      try {
          val assetManager = reactApplicationContext.assets
          val files = assetManager.list("")
          val certFiles = files?.filter { 
              it.endsWith(".cer") || it.endsWith(".crt") || it.endsWith(".pem") 
          } ?: emptyList()
          
          val result = Arguments.createMap().apply {
              putArray("certificates", Arguments.fromList(certFiles))
          }
          
          promise.resolve(result)
          
      } catch (e: Exception) {
          promise.reject("CERT_LIST_ERROR", e.message, e)
      }
  }

  // Helper method to get server certificate info (for debugging)
  @ReactMethod
  fun getCertificateInfo(url: String, promise: Promise) {
      try {
          val connection = java.net.URL(url).openConnection() as HttpsURLConnection
          connection.connectTimeout = 10000
          connection.readTimeout = 10000
          connection.connect()
          
          val certificates = connection.serverCertificates
          val certInfoList = mutableListOf<ReadableMap>()
          
          for (cert in certificates) {
              if (cert is X509Certificate) {
                  val certInfo = Arguments.createMap().apply {
                      putString("subject", cert.subjectDN.toString())
                      putString("issuer", cert.issuerDN.toString())
                      putString("serialNumber", cert.serialNumber.toString())
                      putString("notBefore", cert.notBefore.toString())
                      putString("notAfter", cert.notAfter.toString())
                  }
                  certInfoList.add(certInfo)
              }
          }
          
          val result = Arguments.createMap().apply {
              putArray("certificates", Arguments.fromList(certInfoList))
              putString("url", url)
          }
          
          promise.resolve(result)
          connection.disconnect()
          
      } catch (e: Exception) {
          promise.reject("CERT_INFO_ERROR", e.message, e)
      }
  }

  companion object {
    const val NAME = "ReactNativeTvosSslPinning"
  }
}
