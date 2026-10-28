import { Resvg } from "@resvg/resvg-js";
import { readFile, writeFile, copyFile } from "node:fs/promises";
const root = new URL("../../", import.meta.url);
for (const name of ["logo", "app-icon"]) {
  const input = await readFile(new URL(`branding/${name}.svg`, root));
  await writeFile(
    new URL(`branding/${name}.png`, root),
    new Resvg(input, { fitTo: { mode: "width", value: 1024 } })
      .render()
      .asPng(),
  );
  if (name === "logo")
    await writeFile(
      new URL("branding/mark-128.png", root),
      new Resvg(input, { fitTo: { mode: "width", value: 128 } })
        .render()
        .asPng(),
    );
  if (name === "app-icon")
    await writeFile(
      new URL("branding/preview.png", root),
      new Resvg(input, { fitTo: { mode: "width", value: 256 } })
        .render()
        .asPng(),
    );
}
await copyFile(
  new URL("branding/logo.svg", root),
  new URL("desktop/src/logo.svg", root),
);
console.log("Rendered shared vector mark and application icons.");
