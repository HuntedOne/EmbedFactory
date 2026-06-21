# docs/ — the mentor's local knowledge base

The mentor grounds its advice in reference material kept **here, locally** (these folders are
gitignored and intentionally NOT published, to avoid redistributing third-party copyrighted docs):

- `docs/reference/STMicroelectronics/` — e.g. UM2609 (STM32CubeIDE), UM1718 (STM32CubeMX), `.ioc`
  walkthroughs.
- `docs/reference/Arduino/` — board datasheets, pinout, schematics, CAD.
- `docs/project/` — your project-specific notes and walkthroughs.

Drop the relevant vendor PDFs/HTML for your board and tools into these folders. They stay on your
machine; the mentor reads them via its `Read` tool.

For documentation that lives **online** (e.g. Flux.ai), don't download it here — add the site to
`REFERENCE_DOC_URLS` in `.env`, and the mentor will fetch it (allowlisted) via `WebFetch`.
