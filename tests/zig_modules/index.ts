import { createRequire } from "module";

const require = createRequire(import.meta.url);

export default function requireTestModule(name: string): any {
  return require(`./${name}.node`);
}
