import { NativeModules, Platform } from 'react-native';

export interface PinningOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH';
  headers?: Record<string, string>;
  body?: string;
  timeoutInterval?: number;
  sslPinning?: {
    certs: string[];
  };
  // Any other custom options you expose
  [key: string]: any;
}

export interface PinningResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
  [key: string]: any;
}


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

export function getAvailableCertificates(): string[] {
  return ReactNativeTvosSslPinning.getAvailableCertificates();
}

export function fetchDataWithPinning(url: string, options: PinningOptions): PinningResponse {
  return ReactNativeTvosSslPinning.fetchDataWithPinning(url, options);
}