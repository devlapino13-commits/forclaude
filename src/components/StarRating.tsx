import React from 'react';
import { View, Pressable, Text, StyleSheet } from 'react-native';

interface Props {
  rating: number;
  onChange: (rating: number) => void;
  size?: number;
}

export default function StarRating({ rating, onChange, size = 22 }: Props) {
  return (
    <View style={styles.row}>
      {[1, 2, 3, 4, 5].map((n) => (
        <Pressable key={n} onPress={() => onChange(n === rating ? 0 : n)} hitSlop={6}>
          <Text style={{ fontSize: size, color: n <= rating ? '#f5a623' : '#444' }}>
            {n <= rating ? '★' : '☆'}
          </Text>
        </Pressable>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', gap: 2 },
});
