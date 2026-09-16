import React from 'react';
import { StatusBar } from 'expo-status-bar';
import { NavigationContainer, DarkTheme } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import ContactsListScreen from './src/screens/ContactsListScreen';
import ContactDetailScreen from './src/screens/ContactDetailScreen';
import type { RootStackParamList } from './src/navigation/types';

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function App() {
  return (
    <NavigationContainer theme={DarkTheme}>
      <StatusBar style="light" />
      <Stack.Navigator>
        <Stack.Screen
          name="ContactsList"
          component={ContactsListScreen}
          options={{ title: 'Контакты' }}
        />
        <Stack.Screen
          name="ContactDetail"
          component={ContactDetailScreen}
          options={{ title: 'Контакт' }}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
}
