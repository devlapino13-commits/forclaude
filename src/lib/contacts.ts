import * as Contacts from 'expo-contacts';
import { ContactWithMeta } from './types';
import { getAllMeta } from './store';

export async function requestPermission(): Promise<boolean> {
  const { status } = await Contacts.requestPermissionsAsync();
  return status === 'granted';
}

function daysBetween(iso: string | null): number | null {
  if (!iso) return null;
  const then = new Date(iso).getTime();
  const now = Date.now();
  return Math.floor((now - then) / (1000 * 60 * 60 * 24));
}

export async function loadContactsWithMeta(): Promise<ContactWithMeta[]> {
  const { data } = await Contacts.getContactsAsync({
    fields: [
      Contacts.Fields.PhoneNumbers,
      Contacts.Fields.Emails,
      Contacts.Fields.Image,
    ],
    sort: Contacts.SortTypes.FirstName,
  });

  const metaMap = await getAllMeta();

  return data
    .filter((c) => !!c.id)
    .map((c) => {
      const meta = metaMap[c.id!] ?? { rating: 0, lastContactedAt: null, notes: '', tags: [] };
      return {
        id: c.id!,
        name: c.name || 'Без имени',
        phoneNumbers: (c.phoneNumbers ?? []).map((p) => p.number ?? '').filter(Boolean),
        emails: (c.emails ?? []).map((e) => e.email ?? '').filter(Boolean),
        imageUri: c.image?.uri,
        meta,
        daysSinceContact: daysBetween(meta.lastContactedAt),
      };
    });
}
