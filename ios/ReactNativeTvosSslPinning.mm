#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(ReactNativeTvosSslPinning, NSObject)

// Main method for making network requests with SSL pinning
RCT_EXTERN_METHOD(fetchDataWithPinning:(NSString *)url
                  options:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// Method to extract certificate fingerprint from a hostname
RCT_EXTERN_METHOD(getCertificateFingerprint:(NSString *)hostname
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

// Method to validate certificate against expected fingerprint
RCT_EXTERN_METHOD(validateCertificate:(NSString *)hostname
                  expectedCert:(NSString *)expectedCert
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
                  
+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

@end
