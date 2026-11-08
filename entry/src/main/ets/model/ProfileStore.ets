import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ConnectionProfile, ProfileCodec } from './Profile';

const STORE_NAME: string = 'termzero';
const KEY_PROFILES: string = 'profiles';

/** 连接档案持久化: @ohos.data.preferences 里存一个 JSON 数组字符串。 */
export class ProfileStore {
  static async load(context: Context): Promise<ConnectionProfile[]> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      const stored = await store.get(KEY_PROFILES, '[]');
      return ProfileCodec.fromJson(`${stored}`);
    } catch (e) {
      return [];
    }
  }

  static async save(context: Context, list: ConnectionProfile[]): Promise<void> {
    const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
    await store.put(KEY_PROFILES, ProfileCodec.toJson(list));
    await store.flush();
  }

  static async getById(context: Context, index: number): Promise<ConnectionProfile | null> {
    const list: ConnectionProfile[] = await ProfileStore.load(context);
    if (index < 0 || index >= list.length) {
      return null;
    }
    return list[index];
  }

  static async upsert(context: Context, index: number, profile: ConnectionProfile): Promise<void> {
    const list: ConnectionProfile[] = await ProfileStore.load(context);
    if (index >= 0 && index < list.length) {
      list[index] = profile;
    } else {
      list.push(profile);
    }
    await ProfileStore.save(context, list);
  }

  static async deleteAt(context: Context, index: number): Promise<ConnectionProfile[]> {
    const list: ConnectionProfile[] = await ProfileStore.load(context);
    const next: ConnectionProfile[] = [];
    list.forEach((item: ConnectionProfile, i: number): void => {
      if (i !== index) {
        next.push(item);
      }
    });
    await ProfileStore.save(context, next);
    return next;
  }
}
