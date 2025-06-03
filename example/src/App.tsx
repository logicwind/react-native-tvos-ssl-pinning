import React, { useState, useEffect, type JSX } from 'react';
import { Text, View, StyleSheet } from 'react-native';

import { fetchDataWithPinning, getAvailableCertificates, type PinningOptions } from '@logicwind/react-native-tvos-ssl-pinning';

export default function App(): JSX.Element {
  const [result, setResult] = useState<any>();

  useEffect(() => {
    callApiForData()
  }, []);

  const callApiForData = async (): Promise<void> => {
    try {
      const options: PinningOptions = {
        method: "GET",
        headers: {
          'Content-Type': 'application/json',
        },
        sslPinning: {
          certs: ['cert1', 'cert2'],
        },
        timeoutInterval: 10,
      };

      const availableCertificates = await getAvailableCertificates(); // just if you wanna see the available certificate names.

      const response = await fetchDataWithPinning('https://api_url.com/', options)
      setResult(response?.data)
    } catch (error) {
      // handle error
    } finally {
      // handle finally
    }
  }

  return (
    <View style={styles.container}>
      <Text>Result: {result}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
