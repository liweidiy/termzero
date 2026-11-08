/**
 * TermZero 连接档案模型。
 * 引擎认证方式: 密码 -> SshClient.connect, 私钥 -> SshClient.connectWithKey(私钥内容)。
 */
export const AUTH_PASSWORD: string = 'password';
export const AUTH_KEY: string = 'key';

export class ConnectionProfile {
  name: string = '';
  host: string = '';
  port: number = 22;
  username: string = '';
  /** AUTH_PASSWORD | AUTH_KEY */
  authType: string = AUTH_PASSWORD;
  /** 私钥文件路径(authType == key) */
  keyPath: string = '';
  /** 可选保存的密码(authType == password); 空则终端页现场输入 */
  password: string = '';
}

/** 反序列化用的宽松形态, 字段可能缺失。 */
interface RawProfile {
  name?: string;
  host?: string;
  port?: number;
  username?: string;
  authType?: string;
  keyPath?: string;
  password?: string;
}

export class ProfileCodec {
  static fromJson(text: string): ConnectionProfile[] {
    const result: ConnectionProfile[] = [];
    if (text.length === 0) {
      return result;
    }
    const raw: RawProfile[] = JSON.parse(text) as RawProfile[];
    raw.forEach((item: RawProfile): void => {
      result.push(ProfileCodec.normalize(item));
    });
    return result;
  }

  static toJson(list: ConnectionProfile[]): string {
    return JSON.stringify(list);
  }

  private static normalize(raw: RawProfile): ConnectionProfile {
    const profile: ConnectionProfile = new ConnectionProfile();
    profile.name = ProfileCodec.text(raw.name);
    profile.host = ProfileCodec.text(raw.host);
    profile.username = ProfileCodec.text(raw.username);
    profile.keyPath = ProfileCodec.text(raw.keyPath);
    profile.password = ProfileCodec.text(raw.password);
    const port: number | undefined = raw.port;
    profile.port = (port !== undefined && port > 0 && port < 65536) ? port : 22;
    const auth: string | undefined = raw.authType;
    profile.authType = (auth === AUTH_KEY) ? AUTH_KEY : AUTH_PASSWORD;
    return profile;
  }

  private static text(value: string | undefined): string {
    return value === undefined ? '' : value;
  }
}

/** router.pushUrl 参数: 档案在列表中的下标, -1 表示新建。 */
export class RouteParams {
  index: number = -1;

  constructor(index: number) {
    this.index = index;
  }
}
