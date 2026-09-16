import React, { useCallback, useEffect, useState } from 'react';
import {
  View,
  Text,
  Pressable,
  StyleSheet,
  Linking,
  TextInput,
  ScrollView,
  Alert,
} from 'react-native';
import * as Contacts from 'expo-contacts';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { RootStackParamList } from '../navigation/types';
import { ContactWithMeta } from '../lib/types';
import { loadContactsWithMeta } from '../lib/contacts';
import { markContactedNow, setRating, setNotes } from '../lib/store';
import StarRating from '../components/StarRating';

type Props = NativeStackScreenProps<RootStackParamList, 'ContactDetail'>;

export default function ContactDetailScreen({ route, navigation }: Props) {
  const { contactId } = route.params;
  const [contact, setContact] = useState<ContactWithMeta | null>(null);
  const [notesDraft, setNotesDraft] = useState('');

  const refresh = useCallback(async () => {
    const all = await loadContactsWithMeta();
    const found = all.find((c) => c.id === contactId) ?? null;
    setContact(found);
    setNotesDraft(found?.meta.notes ?? '');
    if (found) navigation.setOptions({ title: found.name });
  }, [contactId, navigation]);

  useEffect(() => {
    refresh();
  }, [refresh]);

  if (!contact) {
    return (
      <View style={styles.center}>
        <Text style={styles.emptyText}>Контакт не найден</Text>
      </View>
    );
  }

  const call = (number: string) => Linking.openURL(`tel:${number}`);
  const sms = (number: string) => Linking.openURL(`sms:${number}`);
  const email = (address: string) => Linking.openURL(`mailto:${address}`);

  const handleMarkContacted = async () => {
    await markContactedNow(contact.id);
    await refresh();
  };

  const handleRating = async (rating: number) => {
    await setRating(contact.id, rating);
    await refresh();
  };

  const handleSaveNotes = async () => {
    await setNotes(contact.id, notesDraft);
    Alert.alert('Сохранено', 'Заметка обновлена.');
  };

  const handleDelete = () => {
    Alert.alert(
      'Удалить контакт',
      `Удалить ${contact.name} из адресной книги телефона? Это действие необратимо.`,
      [
        { text: 'Отмена', style: 'cancel' },
        {
          text: 'Удалить',
          style: 'destructive',
          onPress: async () => {
            await Contacts.removeContactAsync(contact.id);
            navigation.goBack();
          },
        },
      ]
    );
  };

  return (
    <ScrollView style={styles.container} contentContainerStyle={{ padding: 16, gap: 20 }}>
      <View style={styles.section}>
        <Text style={styles.name}>{contact.name}</Text>
        <Text style={styles.sub}>
          {contact.daysSinceContact === null
            ? 'Ещё не отмечали общение'
            : `Последний контакт: ${contact.daysSinceContact} дн. назад`}
        </Text>
      </View>

      <View style={styles.section}>
        <Text style={styles.label}>Рейтинг</Text>
        <StarRating rating={contact.meta.rating} onChange={handleRating} size={30} />
      </View>

      <Pressable style={styles.primaryBtn} onPress={handleMarkContacted}>
        <Text style={styles.primaryBtnText}>Отметить: связался сегодня</Text>
      </Pressable>

      {contact.phoneNumbers.length > 0 && (
        <View style={styles.section}>
          <Text style={styles.label}>Телефоны</Text>
          {contact.phoneNumbers.map((num) => (
            <View key={num} style={styles.actionRow}>
              <Text style={styles.value}>{num}</Text>
              <View style={styles.actionButtons}>
                <Pressable style={styles.smallBtn} onPress={() => call(num)}>
                  <Text style={styles.smallBtnText}>Позвонить</Text>
                </Pressable>
                <Pressable style={styles.smallBtn} onPress={() => sms(num)}>
                  <Text style={styles.smallBtnText}>SMS</Text>
                </Pressable>
              </View>
            </View>
          ))}
        </View>
      )}

      {contact.emails.length > 0 && (
        <View style={styles.section}>
          <Text style={styles.label}>Email</Text>
          {contact.emails.map((addr) => (
            <View key={addr} style={styles.actionRow}>
              <Text style={styles.value}>{addr}</Text>
              <Pressable style={styles.smallBtn} onPress={() => email(addr)}>
                <Text style={styles.smallBtnText}>Написать</Text>
              </Pressable>
            </View>
          ))}
        </View>
      )}

      <View style={styles.section}>
        <Text style={styles.label}>Заметки</Text>
        <TextInput
          style={styles.notesInput}
          multiline
          value={notesDraft}
          onChangeText={setNotesDraft}
          placeholder="Например: подарить на др книгу, интересуется..."
          placeholderTextColor="#777"
        />
        <Pressable style={styles.saveBtn} onPress={handleSaveNotes}>
          <Text style={styles.saveBtnText}>Сохранить заметку</Text>
        </Pressable>
      </View>

      <Pressable style={styles.dangerBtn} onPress={handleDelete}>
        <Text style={styles.dangerBtnText}>Удалить контакт</Text>
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  emptyText: { color: '#aaa' },
  section: { gap: 8 },
  name: { color: '#fff', fontSize: 24, fontWeight: '700' },
  sub: { color: '#999', fontSize: 14 },
  label: { color: '#999', fontSize: 13, textTransform: 'uppercase', letterSpacing: 0.5 },
  value: { color: '#fff', fontSize: 16 },
  actionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: '#1c1c1e',
    borderRadius: 10,
    padding: 12,
  },
  actionButtons: { flexDirection: 'row', gap: 8 },
  smallBtn: { backgroundColor: '#0a84ff', paddingHorizontal: 10, paddingVertical: 6, borderRadius: 8 },
  smallBtnText: { color: '#fff', fontSize: 13, fontWeight: '600' },
  primaryBtn: { backgroundColor: '#4caf7d', padding: 14, borderRadius: 12, alignItems: 'center' },
  primaryBtnText: { color: '#fff', fontWeight: '700', fontSize: 15 },
  notesInput: {
    backgroundColor: '#1c1c1e',
    color: '#fff',
    borderRadius: 10,
    padding: 12,
    minHeight: 90,
    textAlignVertical: 'top',
  },
  saveBtn: { backgroundColor: '#2c2c2e', padding: 10, borderRadius: 10, alignItems: 'center' },
  saveBtnText: { color: '#fff', fontWeight: '600' },
  dangerBtn: { padding: 14, borderRadius: 12, alignItems: 'center', borderWidth: 1, borderColor: '#e05555' },
  dangerBtnText: { color: '#e05555', fontWeight: '700' },
});
