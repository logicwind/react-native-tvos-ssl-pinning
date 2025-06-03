import { NativeModules, Platform } from 'react-native';

const LINKING_ERROR =
  `The package '@logicwind/react-native-tvos-ssl-pinning' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go\n';

const ReactNativeTvosSslPinning = NativeModules.ReactNativeTvosSslPinning
  ? NativeModules.ReactNativeTvosSslPinning
  : new Proxy(
    {},
    {
      get() {
        throw new Error(LINKING_ERROR);
      },
    }
  );

export function getAvailableCertificates() {
  return ReactNativeTvosSslPinning.getAvailableCertificates();
}

export function fetchDataWithPinning(url: string, options: any) {
  return ReactNativeTvosSslPinning.fetchDataWithPinning(url, options);
}