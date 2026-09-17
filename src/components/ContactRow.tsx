import React from 'react';
import { View, Text, Pressable, Image, StyleSheet } from 'react-native';
import { ContactWithMeta } from '../lib/types';

interface Props {
  contact: ContactWithMeta;
  onPress: () => void;
}

function daysLabel(days: number | null): string {
  if (days === null) return 'Нет данных о контакте';
  if (days === 0) return 'Общались сегодня';
  if (days === 1) return 'Общались вчера';
  return `Не общались ${days} дн.`;
}

function urgencyColor(days: number | null): string {
  if (days === null) return '#888';
  if (days >= 60) return '#e05555';
  if (days >= 21) return '#e0a555';
  return '#4caf7d';
}

export default function ContactRow({ contact, onPress }: Props) {
  const initial = contact.name.trim().charAt(0).toUpperCase() || '?';
  return (
    <Pressable style={styles.row} onPress={onPress}>
      {contact.imageUri ? (
        <Image source={{ uri: contact.imageUri }} style={styles.avatar} />
      ) : (
        <View style={styles.avatarFallback}>
          <Text style={styles.avatarText}>{initial}</Text>
        </View>
      )}
      <View style={styles.info}>
        <Text style={styles.name}>{contact.name}</Text>
        <Text style={[styles.days, { color: urgencyColor(contact.daysSinceContact) }]}>
          {daysLabel(contact.daysSinceContact)}
        </Text>
      </View>
      {contact.meta.rating > 0 && (
        <Text style={styles.rating}>{'★'.repeat(contact.meta.rating)}</Text>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 16,
    gap: 12,
  },
  avatar: { width: 44, height: 44, borderRadius: 22 },
  avatarFallback: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#3a3a3c',
    alignItems: 'center',
    justifyContent: 'center',
  },
  avatarText: { color: '#fff', fontWeight: '600', fontSize: 16 },
  info: { flex: 1 },
  name: { fontSize: 16, fontWeight: '500', color: '#fff' },
  days: { fontSize: 13, marginTop: 2 },
  rating: { color: '#f5a623', fontSize: 13 },
});
