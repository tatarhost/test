# HYPERREAL SHADERS v1.0

Реалистичный shader pack для **Minecraft Java Edition 1.20.4** (Iris + Sodium, экспериментально — OptiFine).
Написан с нуля: собственная архитектура, собственные реализации алгоритмов, только настоящий GLSL — без
заглушек и «декоративных» файлов.

> **Честно о технологии.** Пак не использует аппаратную трассировку лучей (DXR / Vulkan RT). Все «RTX-подобные»
> эффекты — SSR, SSGI, мягкие тени, AO, объёмный свет — это программные экранно-пространственные алгоритмы и
> трассировка в карте теней. Они дают близкую к RT картинку там, где это возможно без RT-ядра, и имеют
> ограничения, перечисленные ниже.

* **40 программ** (`*.vsh` / `*.fsh`), 20 полных пар вершинный + фрагментный шейдер
* **26 библиотек** в `shaders/lib`, ~4400 строк GLSL
* **82 опции**, 12 экранов настроек, 6 пресетов, два языка интерфейса (ru / en)
* Пайплайн: `gbuffers → shadow → composite → composite1 → composite2 → composite3 → composite4 → composite5 → final`

---

## 1. Требования

| | Минимум | Комфортно | Максимум |
|---|---|---|---|
| Видеокарта | GTX 750 Ti / RX 550 | GTX 1060 6 ГБ / RX 580 | RTX 3060 Ti / RX 6700 XT и выше |
| VRAM | 4 ГБ | 6–8 ГБ | 8+ ГБ |
| ОЗУ | 8 ГБ (4 ГБ игре) | 16 ГБ (6 ГБ игре) | 16+ ГБ |
| Пресет | LOW | HIGH | ULTRA / EXTREME / CINEMATIC |

* Minecraft **1.20.4**, Java 17.
* **Iris 1.6.0+** и **Sodium 0.5.8+** для 1.20.4 (Fabric или NeoForge).
* Производители: NVIDIA, AMD, Intel — пак не использует vendor-specific расширений и не опирается на
  `GL_ARB_*`, которых нет у вендора. Требуется OpenGL 3.3+ (у всех поддерживаемых карт есть).
* Не требуется: шейдерный компилятор в игре, аппаратный RT, специальные драйверы.

## 2. Установка (Minecraft 1.20.4)

1. Установите Fabric Loader для 1.20.4 и положите в `mods/`:
   * [Sodium](https://modrinth.com/mod/sodium) 0.5.8+
   * [Iris Shaders](https://modrinth.com/mod/iris) 1.6.0+
   * (опционально) Indium, Lithium — совместимы.
2. Скачайте **`HYPERREAL-SHADERS-v1.0.zip`** из раздела [Releases](../../releases).
3. Скопируйте архив **целиком** в папку шейдеров:
   * Windows: `%APPDATA%\.minecraft\shaderpacks\`
   * Linux: `~/.minecraft/shaderpacks/`
   * macOS: `~/Library/Application Support/minecraft/shaderpacks/`
4. В игре: **Параметры → Настройки графики → Наборы шейдеров → HYPERREAL SHADERS v1.0 → Применить**.
5. Выберите пресет: **Настройки шейдеров → внизу список пресетов → HIGH**.

Распаковывать архив не нужно: он уже имеет правильную внутреннюю структуру (`shaders/…` в корне).
Если хотите распаковать — получите папку `shaders`, её нужно положить внутрь папки с именем пака,
например `shaderpacks/HYPERREAL SHADERS v1.0/shaders/…`.

## 3. Реализованные эффекты

Всё перечисленное ниже имеет реальный код в `shaders/`; путь к реализации указан в каждой строке.

### Тени и освещение
| Эффект | Реализация |
|---|---|
| Карта теней с радиальным искажением клип-пространства (больше текселей у камеры) | `shadow.vsh`, `lib/shadows.glsl` |
| PCF 1 / 4 / 9 / 17 выборок с поворотом по шуму | `lib/shadows.glsl` (`pcfShadow`) |
| PCSS — мягкие тени с поиском перекрытий (blocker search) и полутенью по размеру источника | `lib/shadows.glsl` (`shadowBlockerDepth`, `getShadowVisibility`) |
| Normal offset bias + slope scaled depth bias (нет «акне» и «peter panning») | `lib/shadows.glsl` |
| Контактные тени: короткая трассировка в экранном пространстве к источнику | `composite1.fsh` |
| SSAO: 10 выборок по спирали в полусфере, ограничение по глубине | `composite.fsh` |
| SSGI: один отскок непрямого света экранными лучами | `composite.fsh` |
| Цветной свет от блоков и окрашивание света сквозь цветное стекло | `lib/lighting.glsl`, `COLORED_SHADOWS` |
| Динамический свет в руке (факел, фонарь) | `lib/lighting.glsl` (`handLight`), `dynamicHandLight=true` |
| PBR-освещение: GGX + Smith + Schlick Fresnel, энергосберегающий диффуз | `lib/brdf.glsl` |

### Отражения
| Эффект | Реализация |
|---|---|
| SSR: трассировка в экранном пространстве с бинарным уточнением и проверкой по нормали | `composite.fsh` |
| Шероховатые отражения (jitter луча, размытие по шероховатости) | `REFLECTION_ROUGH`, `lib/brdf.glsl` |
| Отражения на воде с фолбэком на небо и облака | `composite1.fsh`, `lib/clouds.glsl` (`cloudLayerReflection`) |
| Отражения на стекле, льду, металле и мокрых поверхностях | `composite1.fsh`, `lib/materials.glsl` |

### Вода
| Эффект | Реализация |
|---|---|
| Волны: 5 направленных синусоид (компактная сумма Герстнера) по мировым XZ | `lib/water.glsl` |
| Аналитические нормали волн + двухслойная капиллярная рябь | `lib/water.glsl` (`waterWaveNormal`, `waterRippleNormal`) |
| Преломление по нормали волны с защитой от выхода за экран | `composite1.fsh` |
| Поглощение по Бугеру–Ламберту по реальной толще воды + рассеяние | `lib/water.glsl` (`waterAbsorption`, `waterBodyColor`) |
| Каустики на дне мелкой воды (анимированный Worley-паттерн) | `lib/water.glsl` (`caustics`) |
| Fresnel-смешивание отражения и преломления | `composite1.fsh` |
| Подводный туман и подводные лучи света | `lib/fog.glsl`, `composite3.fsh` |

### Небо, атмосфера, облака
| Эффект | Реализация |
|---|---|
| Модель однократного рассеяния (Рэлей, Ми, озон) с интегрированием по лучам | `lib/atmosphere.glsl` |
| Диск солнца, диск луны с фазой, звёзды с мерцанием, млечный путь, полярное сияние | `lib/atmosphere.glsl` (`sunDisc`, `moonDisc`, `starField`, `milkyWay`, `aurora`) |
| Объёмные кучевые облака: slab-intersection + рейтрейсинг с FBM-полем плотности | `lib/clouds.glsl` (`raymarchClouds`) |
| Многократное рассеяние в облаках (Beer + powder + ambient fill), самозатенение | `lib/clouds.glsl` (`cloudSampleLight`) |
| Тени от облаков на земле | `lib/clouds.glsl` (`cloudShadowFactor`) |
| Атмосферный туман / воздушная перспектива | `composite3.fsh` |
| Высотный туман, утренняя дымка | `lib/fog.glsl` (`fogDensityAt`) |
| Объёмный свет: god rays через листву и окна, крепускулярные лучи | `composite3.fsh` (`marchFog`) |
| Дождь/гроза: затемнение света, мокрые поверхности, вспышки молний | `lib/lighting.glsl`, `lib/materials.glsl` (`applyWetness`), `LIGHTNING_FLASH` |

### Материалы и растительность
| Эффект | Реализация |
|---|---|
| PBR-ресурспаки в стиле labPBR: карты `_n` и `_s`, автоопределение наличия | `lib/materials.glsl` (`Material`, `buildFrame`, `perturbNormal`) |
| Эвристические материалы для ванильных блоков (металл, камень, снег, стекло, лёд, листва) | `lib/materials.glsl` (`heuristicMaterial`) |
| Светящиеся блоки: свечение + локальная подсветка | `EMISSIVE_BLOCKS`, `lib/lighting.glsl` |
| Подповерхностное рассеяние в листве и тонких растениях | `SUBSURFACE_SCATTERING`, `lib/brdf.glsl` (`diffuseWrapped`) |
| Мокрые поверхности: потемнение + рост глянца, высыхание по `wetness` | `applyWetness` |
| Ветер: трава, цветы, посевы, листва (покачивание блока целиком, без разрывов), келп | `lib/vegetation.glsl`, `lib/vsh_main.glsl` |
| Порывы ветра крупного масштаба | `lib/vegetation.glsl` (`windGust`) |

### Постобработка
| Эффект | Реализация |
|---|---|
| Bright pass + 4×4 downsample | `composite4.fsh` |
| Широкий гауссов bloom (двухпроходное размытие) | `composite5.fsh` |
| Тонмаппинг: ACES (аппроксимация Hill), Reinhard, Uchimura | `lib/post.glsl` (`applyTonemap`) |
| Автоэкспозиция по средней яркости кадра (без истории → без ghosting) | `final.fsh` (`sceneLuminance`, `autoExposure`) |
| Глубина резкости (12 тапов golden-angle, защита от bleed по глубине) | `final.fsh` (`depthOfField`) |
| Смаз движения по репроекции предыдущего кадра | `final.fsh` (`reprojectionVelocity`, `motionBlur`) |
| Блик объектива (ghost + halo с окклюзией по глубине) | `final.fsh` (`lensFlare`) |
| Хроматическая аберрация, виньетка, повышение резкости (CAS-подобное) | `lib/post.glsl` |
| Зерно плёнки, дизеринг перед sRGB | `lib/post.glsl` (`filmGrain`, `ditherNoise`) |
| Цветовые профили: нейтральный, кинематографичный, тёплый, холодный | `lib/post.glsl` (`applyColorGrade`) |

### Утилиты и диагностика
* Отладочные виды (`DEBUG_VIEW`): глубина, нормали, bloom, материал, уровни света, флаги поверхности.
* Единый вход/выход G-buffer (`lib/gbuffer_out.glsl`, `lib/trans_out.glsl`) — нельзя забыть буфер.
* Карта буферов и форматов в одном месте: `lib/buffers.glsl`.

## 4. Настройки

Все 82 опции сгруппированы в 12 экранов: **Тени · Затенение и GI · Отражения · Вода · Небо ·
Облака · Туман и лучи · Материалы · Анимация · Постобработка · Погода · Отладка**.
Полный список с значениями, умолчаниями и стоимостью каждого параметра — в
[docs/SETTINGS.md](docs/SETTINGS.md).

Пресеты (`Настройки шейдеров → пресеты`) задают только параметры производительности, остальные
ваши правки сохраняются:

| Пресет | Кому | Ключевое |
|---|---|---|
| LOW | старое/встроенное видео | тени 1024 + 1 tap, без SSAO/SSGI/SSR/облаков/лучей |
| MEDIUM | средние GPU | тени 2048, PCSS, SSAO, SSR, лучи, облака 1 шаг |
| HIGH | игровые GPU | всё включено, тени 2048, облака 2, SSGI |
| ULTRA | мощные GPU | тени 3072, 17 tap PCF, SSR 48 шагов |
| EXTREME | топовые GPU | тени 4096, дальность 256 блоков, SSR 64, облака ультра |
| CINEMATIC | скриншоты | EXTREME + DoF + motion blur + зерно |

## 5. Совместимость

* **Iris 1.6.0+ / 1.7.x / 1.8.x** на 1.20.4 — основной таргет, протестирован статически по формату
  Iris (см. docs/TESTING.md).
* **Sodium** — полноценно, атрибуты `mc_Entity`, `at_tangent`, `mc_midTexCoord` читаются через
  `vertex-format` Iris.
* **OptiFine 1.20.4 HD U I7+** — экспериментально: пак использует только директивы, которые понимают оба
  загрузчика (`DRAWBUFFERS`, `const int colortexNFormat` в комментарии, `screen`/`sliders`/`profile`,
  `blend.<program>`), но в OptiFine не проверялся.
* Работает на NVIDIA, AMD, Intel.
* Совместимые моды: Iris, Sodium, Indium, Lithium, Starlight-подобные оптимизации.
* **Не совместимо:** другие shader pack одновременно (очевидно), моды, переопределяющие ванильное небо
  и облака нестандартным способом, шейдерные моды для 1.21+ (нужен другой формат uniform'ов).
* PBR-ресурспаки с картами `_n` / `_s` (labPBR) поддерживаются автоматически, без настройки.

## 6. Тестирование

В среде разработки невозможно запустить Minecraft (нет GPU/OpenGL-контекста и клиента), поэтому
проверка выполнена всем доступным статическим инструментарием:

```
python3 tools/compile_shaders.py   # 40/40 programs compiled, 20/20 pairs linked
python3 tools/check_pack.py        # pack structure OK (0 problems, 0 warnings)
```

* Компиляция каждого шейдера `glslangValidator` 11.7.0 (`#version 330 compatibility`).
* Линковка всех 20 пар вершинный+фрагментный (`glslangValidator -l`) — совпадение `varying`.
* Проверка связности буферов: `DRAWBUFFERS` ↔ объявленные выходы, отсутствие framebuffer feedback,
  запрет `colortex0-3` в gbuffers, наличие формата у каждого используемого буфера.
* Проверка `shaders.properties` ↔ `lib/settings.glsl`, переводы (`ru_ru`, `en_us`) для всех экранов и
  опций, `block.properties` ↔ `lib/materials.glsl`.
* Валидация GLSL-фич, на которые опирается пак (`mc_Entity`, `at_tangent`, `gl_TextureMatrix`,
  `texture()`, `layout(location=)`).

Подробный отчёт и инструкция «как повторить» — в [docs/TESTING.md](docs/TESTING.md).

## 7. Известные ограничения

1. **Это не аппаратный RT.** SSR/SSGI видят только то, что есть в кадре: объект за спиной или за
   границей экрана не отразится. Отражения вне экрана подменяются небом и облаками.
2. **SSGI — один отскок** и без временнóго накопления: намеренно, чтобы не было ghosting. Цветной
   bleed поэтому мягче, чем у RT.
3. **Тени — одна карта** (без каскадов: shader pack не может их создать). Дальность 96–320 блоков
   настраивается; дальше — только ambient.
4. **Нет TAA/TAAU** и нет истории кадра вообще: любой эффект, требующий накопления, реализован
   пространственно. Плюс — нет ghosting и «шлейфов» при движении, минус — SSGI/SSR чуть шумнее.
5. **Nether / End**: атмосферная модель рассчитана на Overworld; в других измерениях небо берётся
   из `fogColor` и `netherSky` (стилизованно), звёзд и млечного пути там нет.
6. **DoF / motion blur / зерно** по умолчанию выключены (кроме пресета CINEMATIC) — они мешают игре.
7. **Фаза луны и звёзды** процедурные, не текстуры: диск луны собран из `moonPhase`.
8. **Прозрачные блоки**: пак не ломает ванильные прозрачные блоки — их геометрия не модифицируется,
   меняется только шейдинг. Кастомные модели с нестандартным alpha-blending могут выглядеть иначе,
   чем в ваниле.
9. **Вода** смещается только по вертикали и зависит от мировых XZ — это гарантирует герметичность
   поверхности, но исключает горизонтальные «горбы» Герстнера.
10. FPS: EXTREME на 1440p требует ~8 ГБ VRAM и топовую карту; при нехватке VRAM драйвер может
    сбросить пак — начните с HIGH.

## 8. Структура репозитория

```
shaders/                    # содержимое shader pack (то, что попадает в ZIP)
  shaders.properties        # экраны, слайдеры, пресеты, состояние рендера
  block.properties          # id блоков для материалов и растительности
  gbuffers_*.{vsh,fsh}      # G-буфер (terrain, entities, hand, water, weather, sky, cloud, particle)
  shadow.{vsh,fsh}          # проход карты теней
  composite{,1..5}.{vsh,fsh}# анализ, шейдинг, облака, туман, bloom
  final.{vsh,fsh}           # постобработка и вывод на экран
  lib/                      # 26 модулей (см. docs/ARCHITECTURE.md)
  lang/{ru_ru,en_us}.lang   # локализация настроек
docs/                       # документация
tools/                      # валидаторы и сборка ZIP (в шейдерпак не входят)
```

## 9. Лицензия

MIT — см. [LICENSE](LICENSE). Сторонняя библиотека GLSL не копировалась; формулы (ACES fit,
Uchimura, labPBR-соглашение, Gerstner/Bouguer) — общеизвестные математические модели, реализованные
самостоятельно в этом репозитории.

---

# English summary

**HYPERREAL SHADERS v1.0** is an original realistic shader pack for Minecraft Java 1.20.4
(Iris + Sodium, experimental OptiFine support). It is written from scratch: 40 GLSL programs,
26 library modules, 82 options, 12 option screens, 6 presets, ru/en localisation.

Features: distorted shadow map with PCF/PCSS and contact shadows, SSAO + single bounce SSGI,
screen space reflections with rough reflections, physically based water (Gerstner waves, Beer–Lambert
absorption, refraction, caustics, underwater fog and god rays), single scattering atmosphere with sun,
moon phase, stars, milky way and aurora, ray marched volumetric clouds with self shadowing and cloud
shadows, volumetric fog and light shafts, labPBR material support, wind animation, full post processing
chain (bloom, ACES/Reinhard/Uchimura, auto exposure, DoF, motion blur, lens flare, CA, vignette,
sharpening, grain, dithering, colour profiles).

Everything is validated statically: `glslangValidator` compiles all 40 programs, links all 20
vertex/fragment pairs, and `tools/check_pack.py` verifies buffer wiring, options, translations and
block ids. Minecraft itself could not be launched in the build environment — see docs/TESTING.md.

Not hardware ray tracing: SSR/SSGI are screen space techniques. See the limitations list above.

Install: drop the release ZIP into `shaderpacks/`, enable with Iris, pick a preset.
