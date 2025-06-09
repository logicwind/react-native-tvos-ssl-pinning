# @logicwind/react-native-tvos-ssl-pinning

React-Native ssl pinning on tvos using OkHttp 3 in Android, and URLSession-based custom implementation on tvOS.


## Getting started

`$ npm install @logicwind/react-native-tvos-ssl-pinning --save`

### Install pods for ios
`$ cd ios && pod install && cd ..`

### Mostly automatic installation

> If you are using `React Native 0.60.+` [the link should happen automatically](https://github.com/react-native-community/cli/blob/master/docs/autolinking.md). in iOS run pod install

`$ react-native link @logicwind/react-native-tvos-ssl-pinning`

## Usage

#### Create the certificates:

1. openssl s_client -showcerts -servername example.com -connect example.com:443 </dev/null

2. Copy the certificate (Usally the first one in the chain), and paste it using nano or other editor like so , nano mycert.pem
3. convert it to .cer with this command
openssl x509 -in mycert.pem -outform der -out mycert.cer 
```
For more ways to obtain the server certificate please refer:
https://stackoverflow.com/questions/7885785/using-openssl-to-get-the-certificate-from-a-server
```
#### iOS
 - Drag mycert.cer to Xcode project, mark your target and 'Copy items if needed'
 - Your certificate will be automatically detect from the target
 
#### Android
 - Place your .cer files under src/main/assets/.
 - Your certificate will be automatically detect from the target

 ### Certificate Pinning

```javascript
import { fetchDataWithPinning, getAvailableCertificates } from '@logicwind/react-native-tvos-ssl-pinning';

fetchDataWithPinning(url, {
	method: "POST" ,
	timeoutInterval: communication_timeout, // milliseconds
	body: body,
	sslPinning: {
		certs: ["cert1","cert2"] // your certificates name (without extension), for example cert1.cer, cert2.cer
	},
	headers: {
		Accept: "application/json; charset=utf-8", "Access-Control-Allow-Origin": "*", "e_platform": "mobile",
	}
})
.then(response => {
	console.log(`response received ${response}`)
})
.catch(err => {
	console.log(`error: ${err}`)
})

// if you want to see the attached certificates
const result = await getAvailableCertificates();
```

## react-native-tvos-ssl-pinning is crafted mindfully at [Logicwind](https://www.logicwind.com?utm_source=github&utm_medium=github.com-logicwind&utm_campaign=react-native-tvos-ssl-pinning)

We are a 130+ people company developing and designing multiplatform applications using the Lean & Agile methodology. To get more information on the solutions that would suit your needs, feel free to get in touch by [email](mailto:sales@logicwind.com) or through or [contact form](https://www.logicwind.com/contact-us?utm_source=github&utm_medium=github.com-logicwind&utm_campaign=react-native-tvos-ssl-pinning)!

We will always answer you with pleasure 😁

## License
This project is licensed under the terms of the MIT license.
