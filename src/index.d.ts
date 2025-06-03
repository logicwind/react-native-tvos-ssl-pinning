declare module '@logicwind/react-native-tvos-ssl-pinning' {
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
    }

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
