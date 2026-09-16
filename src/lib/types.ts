export interface ContactMeta {
  rating: number; // 0-5, 0 = not rated
  lastContactedAt: string | null; // ISO date string
  notes: string;
  tags: string[];
}

export interface ContactWithMeta {
  id: string;
  name: string;
  phoneNumbers: string[];
  emails: string[];
  imageUri?: string;
  meta: ContactMeta;
  daysSinceContact: number | null;
}

export const EMPTY_META: ContactMeta = {
  rating: 0,
  lastContactedAt: null,
  notes: '',
  tags: [],
};
