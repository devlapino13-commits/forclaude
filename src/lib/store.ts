import AsyncStorage from '@react-native-async-storage/async-storage';
import { ContactMeta, EMPTY_META } from './types';

const STORAGE_KEY = '@contact_tracker/meta';

type MetaMap = Record<string, ContactMeta>;

let cache: MetaMap | null = null;

async function load(): Promise<MetaMap> {
  if (cache) return cache;
  const raw = await AsyncStorage.getItem(STORAGE_KEY);
  cache = raw ? JSON.parse(raw) : {};
  return cache!;
}

async function persist(map: MetaMap): Promise<void> {
  cache = map;
  await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(map));
}

export async function getAllMeta(): Promise<MetaMap> {
  return { ...(await load()) };
}

export async function getMeta(contactId: string): Promise<ContactMeta> {
  const map = await load();
  return map[contactId] ?? { ...EMPTY_META };
}

export async function setMeta(contactId: string, meta: ContactMeta): Promise<void> {
  const map = await load();
  map[contactId] = meta;
  await persist(map);
}

export async function markContactedNow(contactId: string): Promise<ContactMeta> {
  const map = await load();
  const current = map[contactId] ?? { ...EMPTY_META };
  const updated: ContactMeta = { ...current, lastContactedAt: new Date().toISOString() };
  map[contactId] = updated;
  await persist(map);
  return updated;
}

export async function setRating(contactId: string, rating: number): Promise<ContactMeta> {
  const map = await load();
  const current = map[contactId] ?? { ...EMPTY_META };
  const updated: ContactMeta = { ...current, rating };
  map[contactId] = updated;
  await persist(map);
  return updated;
}

export async function setNotes(contactId: string, notes: string): Promise<ContactMeta> {
  const map = await load();
  const current = map[contactId] ?? { ...EMPTY_META };
  const updated: ContactMeta = { ...current, notes };
  map[contactId] = updated;
  await persist(map);
  return updated;
}
