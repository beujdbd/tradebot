import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const DATA_DIR = path.join(ROOT_DIR, 'data');
export const ENV_FILE = path.join(ROOT_DIR, '.env');
export const ENV_EXAMPLE_FILE = path.join(ROOT_DIR, '.env.example');
