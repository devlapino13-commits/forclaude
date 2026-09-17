import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  View,
  Text,
  TextInput,
  FlatList,
  StyleSheet,
  Pressable,
  ActivityIndicator,
  RefreshControl,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import ContactRow from '../components/ContactRow';
import { loadContactsWithMeta, requestPermission } from '../lib/contacts';
import { ContactWithMeta } from '../lib/types';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { RootStackParamList } from '../navigation/types';

type SortMode = 'neglected' | 'rating' | 'name';

type Props = NativeStackScreenProps<RootStackParamList, 'ContactsList'>;

export default function ContactsListScreen({ navigation }: Props) {
  const [contacts, setContacts] = useState<ContactWithMeta[]>([]);
  const [loading, setLoading] = useState(true);
  const [permissionDenied, setPermissionDenied] = useState(false);
  const [query, setQuery] = useState('');
  const [sortMode, setSortMode] = useState<SortMode>('neglected');
  const [onlyRated, setOnlyRated] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    const granted = await requestPermission();
    if (!granted) {
      setPermissionDenied(true);
      setLoading(false);
      return;
    }
    setPermissionDenied(false);
    const data = await loadContactsWithMeta();
    setContacts(data);
    setLoading(false);
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  const filtered = useMemo(() => {
    let list = contacts;
    if (query.trim()) {
      const q = query.trim().toLowerCase();
      list = list.filter(
        (c) =>
          c.name.toLowerCase().includes(q) ||
          c.phoneNumbers.some((p) => p.includes(q))
      );
    }
    if (onlyRated) {
      list = list.filter((c) => c.meta.rating > 0);
    }
    const sorted = [...list];
    if (sortMode === 'neglected') {
      sorted.sort((a, b) => {
        const da = a.daysSinceContact ?? Number.MAX_SAFE_INTEGER;
        const db = b.daysSinceContact ?? Number.MAX_SAFE_INTEGER;
        return db - da;
      });
    } else if (sortMode === 'rating') {
      sorted.sort((a, b) => b.meta.rating - a.meta.rating);
    } else {
      sorted.sort((a, b) => a.name.localeCompare(b.name));
    }
    return sorted;
  }, [contacts, query, sortMode, onlyRated]);

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator color="#fff" />
      </View>
    );
  }

  if (permissionDenied) {
    return (
      <View style={styles.center}>
        <Text style={styles.emptyText}>
          Нужен доступ к контактам, чтобы приложение работало.
        </Text>
        <Pressable style={styles.retryBtn} onPress={load}>
          <Text style={styles.retryText}>Запросить доступ снова</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <TextInput
        style={styles.search}
        placeholder="Поиск по имени или номеру"
        placeholderTextColor="#888"
        value={query}
        onChangeText={setQuery}
      />
      <View style={styles.filters}>
        <SortChip label="Давно не общались" active={sortMode === 'neglected'} onPress={() => setSortMode('neglected')} />
        <SortChip label="По рейтингу" active={sortMode === 'rating'} onPress={() => setSortMode('rating')} />
        <SortChip label="По имени" active={sortMode === 'name'} onPress={() => setSortMode('name')} />
      </View>
      <Pressable style={styles.toggle} onPress={() => setOnlyRated((v) => !v)}>
        <Text style={[styles.toggleText, onlyRated && styles.toggleTextActive]}>
          {onlyRated ? '☑' : '☐'} Только с рейтингом
        </Text>
      </Pressable>
      <FlatList
        data={filtered}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <ContactRow
            contact={item}
            onPress={() => navigation.navigate('ContactDetail', { contactId: item.id })}
          />
        )}
        refreshControl={<RefreshControl refreshing={false} onRefresh={load} tintColor="#fff" />}
        ListEmptyComponent={
          <View style={styles.center}>
            <Text style={styles.emptyText}>Контакты не найдены</Text>
          </View>
        }
        contentContainerStyle={filtered.length === 0 ? styles.emptyContainer : undefined}
      />
    </View>
  );
}

function SortChip({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable style={[styles.chip, active && styles.chipActive]} onPress={onPress}>
      <Text style={[styles.chipText, active && styles.chipTextActive]}>{label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24, gap: 16 },
  emptyContainer: { flexGrow: 1 },
  emptyText: { color: '#aaa', textAlign: 'center', fontSize: 15 },
  search: {
    margin: 12,
    marginBottom: 6,
    backgroundColor: '#1c1c1e',
    color: '#fff',
    borderRadius: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  filters: { flexDirection: 'row', gap: 8, paddingHorizontal: 12, marginBottom: 6 },
  chip: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 16,
    backgroundColor: '#1c1c1e',
  },
  chipActive: { backgroundColor: '#0a84ff' },
  chipText: { color: '#aaa', fontSize: 13 },
  chipTextActive: { color: '#fff', fontWeight: '600' },
  toggle: { paddingHorizontal: 16, paddingBottom: 6 },
  toggleText: { color: '#888', fontSize: 13 },
  toggleTextActive: { color: '#0a84ff' },
  retryBtn: { backgroundColor: '#0a84ff', paddingHorizontal: 20, paddingVertical: 10, borderRadius: 10 },
  retryText: { color: '#fff', fontWeight: '600' },
});
