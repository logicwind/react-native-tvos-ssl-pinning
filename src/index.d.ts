import { PinningOptions, PinningResponse } from './index'
declare module '@logicwind/react-native-tvos-ssl-pinning' {
    /**
     * Returns a list of available certificate names bundled with the app.
     */
    export function getAvailableCertificates(): Promise<string[]>;

    /**
     * Performs a network request with SSL pinning.
     * 
     * @param url The request URL
     * @param options Fetch or request options with pinning configuration
     */
    export function fetchDataWithPinning(
        url: string,
        options: PinningOptions
    ): Promise<PinningResponse>;
}
