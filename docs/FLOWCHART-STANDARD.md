# Fluent 2 flowchart design standard

## TLDR/BLUF

**What this is.** The owner's Fluent 2 Flowchart Design Spec, version 1.0.0, stored whole as this
project's standard for flowcharts. It carries design tokens, nine shape definitions, three status
variants, arrow and connector styles, dark-mode overrides and a component API.

**Why you should care.** Section 7 promises WCAG AA contrast. Measured against the spec's own token
values, 18 pairings miss it. The audit names both sides of each pairing, so you know which ones
before you build a component.

**How to use it.** Read [the contrast audit](#contrast-audit-against-section-7) first, then build
from [the specification](#the-specification-as-supplied) below it.

---

## Where this came from

| Field | Value |
|---|---|
| Title | Fluent2 Flowchart Design Spec |
| Version | 1.0.0 |
| Status in the source | Handoff-Ready |
| Supplied by | the project owner |
| Supplied on | 2026-08-31 |
| Stored here on | 2026-08-31 |

The spec is the owner's text. Nothing in it was reworded, renumbered or retuned to fit this page.

## What changed between the supplied file and the copy below

| Change | Why |
|---|---|
| Every heading dropped one level, so `#` became `##` | One H1 per page, which is what the site title is built from |
| Nothing else | Tables, token names, token values and prose are byte-for-byte the source |

**The supplied file carried no emoji and no non-ASCII character of any kind.** A scan of all 473
lines returned an empty set, so no glyph was stripped and none was lost.

Sections 4.1, 4.2 and 4.3 already name the Fluent icon token for each status:
`CheckmarkCircle16Filled`, `Warning16Filled` and `DismissCircle16Filled`. That name is what an
implementer needs.

## Contrast audit against section 7

Every ratio below was computed with the WCAG relative-luminance formula over the spec's own hex
values, on 2026-08-31. Both sides of each pairing are named, because a ratio without its background
is not a measurement.

### What section 7 promises, and what that pulls in

Section 7 writes one contrast sentence, and it covers text only: 4.5:1 for normal text, 3:1 for
large text at 18pt or above. It does not name graphics.

It does say the combinations must meet WCAG AA. WCAG 2.1 AA includes SC 1.4.11 Non-text Contrast at
3:1, which covers a border that carries meaning. So the stroke rows below are in scope.

**The large-text clause applies to nothing in this spec.** WCAG counts text as large at 18pt (24px),
or 14pt bold (18.66px). The biggest label token here is `fontSizeBase400` at 16px.

Every label in the spec is therefore normal text and needs 4.5:1. The 3:1 line in section 7 is dead
wording, not a relaxation any shape can claim.

### Light palette, text at 4.5 to 1

| Foreground | Background | Ratio | Verdict |
|---|---|---|---|
| `colorPaletteGreenForeground2` `#107c10` | `colorPaletteGreenBackground2` `#e6f4ea` | 4.73 | PASS |
| `colorPaletteYellowForeground2` `#835b00` | `colorPaletteYellowBackground2` `#fff4ce` | 5.51 | PASS |
| `colorPaletteRedForeground2` `#c50f1f` | `colorPaletteRedBackground2` `#fde7e9` | 5.14 | PASS |
| `colorNeutralForeground1` `#242424` | `colorNeutralBackground1` `#ffffff` | 15.52 | PASS |
| `colorNeutralForeground1` `#242424` | `colorNeutralBackground2` `#f5f5f5` | 14.24 | PASS |
| `colorNeutralForeground2` `#616161` | `colorNeutralBackground1` `#ffffff` | 6.19 | PASS |
| `colorNeutralForeground2` `#616161` | `colorNeutralBackground2` `#f5f5f5` | 5.68 | PASS |
| `colorNeutralForegroundOnBrand` `#ffffff` | `colorBrandBackground` `#0f6cbd` | 5.38 | PASS |
| `colorNeutralForegroundOnBrand` `#ffffff` | `colorBrandBackgroundHover` `#115ea3` | 6.66 | PASS |
| `colorNeutralForegroundDisabled` `#bdbdbd` | `colorNeutralBackground2` `#f5f5f5` | 1.72 | Fails the number, exempt |

The disabled row is the one exemption. WCAG 1.4.3 excludes text that is part of an inactive control,
so it is not counted among the 18 failures.

### Light palette, the 80 percent sublabel

Sections 4.1, 4.2 and 4.3 set the status sublabel to its foreground token at 80 percent opacity.
Composited over its own fill, that is a different colour, and it is 12px normal text.

| Effective foreground | Background | Ratio | Verdict |
|---|---|---|---|
| `colorPaletteGreenForeground2` at 80% = `#3b943c` | `colorPaletteGreenBackground2` `#e6f4ea` | 3.37 | FAIL |
| `colorPaletteYellowForeground2` at 80% = `#9c7a29` | `colorPaletteYellowBackground2` `#fff4ce` | 3.65 | FAIL |
| `colorPaletteRedForeground2` at 80% = `#d03a47` | `colorPaletteRedBackground2` `#fde7e9` | 4.06 | FAIL |

### Light palette, graphics at 3 to 1

| Stroke | Surface behind it | Ratio | Verdict |
|---|---|---|---|
| `colorNeutralStroke1` `#d1d1d1` | `colorNeutralBackground1` `#ffffff` | 1.53 | FAIL |
| `colorNeutralStroke1` `#d1d1d1` | `colorNeutralBackground2` `#f5f5f5` | 1.40 | FAIL |
| `colorNeutralStroke2` `#e0e0e0` | `colorNeutralBackground1` `#ffffff` | 1.32 | FAIL |
| `colorNeutralStroke2` `#e0e0e0` | `colorNeutralBackground2` `#f5f5f5` | 1.21 | FAIL |
| `colorBrandStroke1` `#0f6cbd` | `colorNeutralBackground1` `#ffffff` | 5.38 | PASS |
| `colorPaletteGreenBorderActive` `#107c10` | `colorNeutralBackground1` `#ffffff` | 5.37 | PASS |
| `colorPaletteYellowBorderActive` `#835b00` | `colorNeutralBackground1` `#ffffff` | 6.07 | PASS |
| `colorPaletteRedBorderActive` `#c50f1f` | `colorNeutralBackground1` `#ffffff` | 6.07 | PASS |
| `colorPaletteGreenBorderActive` `#107c10` | `colorPaletteGreenBackground2` `#e6f4ea` | 4.73 | PASS |
| `colorPaletteYellowBorderActive` `#835b00` | `colorPaletteYellowBackground2` `#fff4ce` | 5.51 | PASS |
| `colorPaletteRedBorderActive` `#c50f1f` | `colorPaletteRedBackground2` `#fde7e9` | 5.14 | PASS |

**The default shape has no visible edge.** Section 2 fills a resting shape with
`colorNeutralBackground1` and borders it with `colorNeutralStroke1` at 1px. On a canvas of the same
`#ffffff`, that border is the only thing separating shape from page, at 1.53:1.

### Dark palette, text at 4.5 to 1

| Foreground | Background | Ratio | Verdict |
|---|---|---|---|
| `colorPaletteGreenForeground2` `#54b054` | `colorPaletteGreenBackground2` `#052505` | 6.06 | PASS |
| `colorPaletteYellowForeground2` `#fce100` | `colorPaletteYellowBackground2` `#2c2200` | 11.91 | PASS |
| `colorPaletteRedForeground2` `#f1707b` | `colorPaletteRedBackground2` `#3b0509` | 6.06 | PASS |
| `colorNeutralForeground1` `#ffffff` | `colorNeutralBackground1` `#1f1f1f` | 16.48 | PASS |
| `colorNeutralForeground1` `#ffffff` | `colorNeutralBackground2` `#2c2c2c` | 13.97 | PASS |
| `colorNeutralForeground2` `#ababab` | `colorNeutralBackground1` `#1f1f1f` | 7.18 | PASS |
| `colorNeutralForeground2` `#ababab` | `colorNeutralBackground2` `#2c2c2c` | 6.08 | PASS |
| `colorNeutralForegroundOnBrand` `#000000` | `colorBrandBackground` `#479ef5` | 7.48 | PASS |
| `colorNeutralForegroundOnBrand` `#000000` | `colorBrandBackgroundHover` `#115ea3` | 3.15 | FAIL |
| `colorNeutralForegroundDisabled` `#bdbdbd` | `colorNeutralBackground2` `#2c2c2c` | 7.43 | PASS |

### Dark palette, the 80 percent sublabel

| Effective foreground | Background | Ratio | Verdict |
|---|---|---|---|
| `colorPaletteGreenForeground2` at 80% = `#449444` | `colorPaletteGreenBackground2` `#052505` | 4.37 | FAIL |
| `colorPaletteYellowForeground2` at 80% = `#d2bb00` | `colorPaletteYellowBackground2` `#2c2200` | 8.12 | PASS |
| `colorPaletteRedForeground2` at 80% = `#cd5b64` | `colorPaletteRedBackground2` `#3b0509` | 4.35 | FAIL |

### Dark palette, graphics at 3 to 1

| Stroke | Surface behind it | Ratio | Verdict |
|---|---|---|---|
| `colorNeutralStroke1` `#404040` | `colorNeutralBackground1` `#1f1f1f` | 1.59 | FAIL |
| `colorNeutralStroke1` `#404040` | `colorNeutralBackground2` `#2c2c2c` | 1.35 | FAIL |
| `colorNeutralStroke2` `#333333` | `colorNeutralBackground1` `#1f1f1f` | 1.30 | FAIL |
| `colorNeutralStroke2` `#333333` | `colorNeutralBackground2` `#2c2c2c` | 1.11 | FAIL |
| `colorBrandStroke1` `#479ef5` | `colorNeutralBackground1` `#1f1f1f` | 5.87 | PASS |
| `colorPaletteGreenBorderActive` `#107c10` | `colorNeutralBackground1` `#1f1f1f` | 3.07 | PASS |
| `colorPaletteYellowBorderActive` `#835b00` | `colorNeutralBackground1` `#1f1f1f` | 2.72 | FAIL |
| `colorPaletteRedBorderActive` `#c50f1f` | `colorNeutralBackground1` `#1f1f1f` | 2.72 | FAIL |
| `colorPaletteGreenBorderActive` `#107c10` | `colorPaletteGreenBackground2` `#052505` | 3.07 | PASS |
| `colorPaletteYellowBorderActive` `#835b00` | `colorPaletteYellowBackground2` `#2c2200` | 2.59 | FAIL |
| `colorPaletteRedBorderActive` `#c50f1f` | `colorPaletteRedBackground2` `#3b0509` | 2.86 | FAIL |

### Five tokens have no dark override, and two failures follow from that

Section 6 lists 15 override rows. These five tokens appear in section 1 and in no override row, so a
dark theme built from section 6 alone keeps their light values:

| Token | Value it keeps in dark mode |
|---|---|
| `colorBrandBackgroundHover` | `#115ea3` |
| `colorPaletteGreenBorderActive` | `#107c10` |
| `colorPaletteRedBorderActive` | `#c50f1f` |
| `colorPaletteYellowBorderActive` | `#835b00` |
| `colorNeutralForegroundDisabled` | `#bdbdbd` |

`colorNeutralForegroundOnBrand` flips to `#000000` in dark mode while `colorBrandBackgroundHover`
stays `#115ea3`. Black on that blue is 3.15:1, so a hovered brand shape loses its label.

The three status border tokens stay at their light values against dark fills. Two of them land below
3:1 there, which is the second consequence of the same gap.

### The findings, and what to do about them

**Do not edit the token values in the copy below.** They are the owner's, and the record of what was
supplied is worth more than a patched table. These are findings against the spec.

| Finding | Where | Count |
|---|---|---|
| The 80 percent sublabel drops below 4.5:1 | Sections 4.1, 4.2 and 4.3, both palettes | 5 |
| Black label on the unoverridden brand hover fill | Section 6 with section 2 | 1 |
| A neutral stroke never reaches 3:1 against either surface | Sections 1.1 and 6 | 8 |
| A status border below 3:1 on a dark surface | The section 6 gap | 4 |

That is 18 pairings. An implementer has four decisions to make before shipping a component:

1. Render the status sublabel at full opacity, or pick a darker value for it. The 80 percent rule
   costs the label its contrast in four of six cases.
2. Give `colorBrandBackgroundHover` a dark override, or keep the label white on it in dark mode.
3. Do not let a neutral stroke be the only cue that a shape exists. Pair it with the shadow tokens
   from section 1.4, or with a fill that differs from the canvas.
4. Give the three status border tokens dark overrides. Section 6 sets their matching foreground
   tokens and stops there.

The focus ring in section 7 is the one control that holds throughout. `colorBrandStroke1` measures
5.38:1 in light and 5.87:1 in dark against `colorNeutralBackground1`.

## The superseded Fluent 2 handoff

An earlier alias-token document from the same owner mapped Fluent 2 tokens to diagram roles. Its
token names match this spec. Several of its values do not.

**It is superseded, not deleted.** A reader holding a copy needs to know it is no longer current.

| Token | Earlier value | This spec | Effect |
|---|---|---|---|
| `colorBrandBackground` | `#0078D4` | `#0f6cbd` | A white label goes from 4.53:1 to 5.38:1 |
| `colorNeutralForeground2` | `#737373` | `#616161` | A secondary label goes from 4.46:1 to 6.19:1 |
| `colorNeutralBackground1` | `#F8F8F8` | `#ffffff` | The default surface is now pure white |

The earlier pairing of `#737373` on its own `#F8F8F8` measured 4.46:1, under the 4.5 that document
promised. Against `#f5f5f5` it measured 4.35:1.

This spec's `#616161` is darker and clears the threshold on every background it is assigned to. That
half of the older document's problem is fixed.

**Only the three values above were supplied to this session.** The earlier document's full token list
was not, so this page cannot say whether its other values changed.

### Seven more failing pairings from the earlier palettes

The full material reached another session the same day, so the gap above is now partly closed. Two
palettes were supplied on 2026-08-31 for restyling a working-model diagram: Microsoft **Fluent**, a
hex palette with a role table, and Microsoft **Fluent 2**, the alias-token document named above.

Each maps a token to a job, and each demands WCAG AA at 4.5 to 1 in its own accessibility section.
**Seven assignments cannot meet it.**

| Foreground | Background | Ratio | Target | Assigned role |
|---|---|---|---|---|
| Gray 70 `#737373` | Brand Tint 20 `#C7E0F4` | **3.48** | 4.5 | secondary text |
| Gray 70 `#737373` | Gray 8 `#F2F2F2` | **4.24** | 4.5 | secondary text |
| Gray 70 `#737373` | Gray 32 `#C8C8C8` | **2.83** | 4.5 | secondary text on a panel |
| Gray 100 `#1F1F1F` | Brand `#0078D4` | **3.64** | 4.5 | text on every process step |
| White `#FFFFFF` | Shared Orange fg `#B8860B` | **3.25** | 4.5 | the obvious repair for a pale fill |
| Gray 36 `#C2C2C2` | Gray 4 `#F8F8F8` | **1.68** | 3.0 | optional-path strokes |
| Gray 20 `#DEDEDE` | Gray 4 `#F8F8F8` | **1.27** | 3.0 | note connectors |

The last two rows are graphics rather than text, so their target is the 3 to 1 of SC 1.4.11, the
same clause the stroke rows above are measured against.

**Four corrections held when the palettes were applied.** They are stated as rules because each one
survived a restyle:

- Secondary text goes one step darker than the palette assigns.
- Hairline strokes go to a mid grey near 3 to 1, not the near-invisible light greys.
- Light greys serve as panel fills, never as a surface behind text.
- Text on a brand-filled shape takes the on-brand token, never the neutral foreground.

**The method was the lowest ratio, not a spot check.** Every pairing that actually occurs in the
restyled diagram was measured in both themes, and the lowest ratio across them decides. Sampling a
few representative pairs passes a palette whose worst case is the one nobody sampled.

**Every row above names both sides, and that is the point.** An earlier statement of these seven
figures named no background, and four of them did not reproduce. The conclusion survived
recomputation and got worse. The figures did not survive it at all.

## Implementing the dark palette in CSS

Define the whole light palette on bare `:root`. Redefine only the token values under the two dark
selectors, and never give a colour its only definition inside a media block or a theme block.

The viewer has three states, not two. An explicit choice stamps `data-theme` on the root element,
and the default system setting stamps nothing at all.

```css
:root {
  /* The complete light palette from section 1.1. Every token gets its value here. */
  --colorNeutralBackground1: #ffffff;
  --colorNeutralBackground2: #f5f5f5;
  --colorNeutralStroke1: #d1d1d1;
  --colorNeutralStroke2: #e0e0e0;
  --colorBrandBackground: #0f6cbd;
  --colorBrandBackgroundHover: #115ea3;
  --colorBrandStroke1: #0f6cbd;
  --colorPaletteGreenBackground2: #e6f4ea;
  --colorPaletteGreenForeground2: #107c10;
  --colorPaletteGreenBorderActive: #107c10;
  --colorPaletteRedBackground2: #fde7e9;
  --colorPaletteRedForeground2: #c50f1f;
  --colorPaletteRedBorderActive: #c50f1f;
  --colorPaletteYellowBackground2: #fff4ce;
  --colorPaletteYellowForeground2: #835b00;
  --colorPaletteYellowBorderActive: #835b00;
  --colorNeutralForeground1: #242424;
  --colorNeutralForeground2: #616161;
  --colorNeutralForegroundOnBrand: #ffffff;
  --colorNeutralForegroundDisabled: #bdbdbd;
}

/* System dark, unless the viewer has explicitly chosen light. Values only. */
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --colorNeutralBackground1: #1f1f1f;
    --colorNeutralBackground2: #2c2c2c;
    --colorNeutralStroke1: #404040;
    --colorNeutralStroke2: #333333;
    --colorNeutralForeground1: #ffffff;
    --colorNeutralForeground2: #ababab;
    --colorBrandBackground: #479ef5;
    --colorBrandStroke1: #479ef5;
    --colorNeutralForegroundOnBrand: #000000;
    --colorPaletteGreenBackground2: #052505;
    --colorPaletteGreenForeground2: #54b054;
    --colorPaletteYellowBackground2: #2c2200;
    --colorPaletteYellowForeground2: #fce100;
    --colorPaletteRedBackground2: #3b0509;
    --colorPaletteRedForeground2: #f1707b;
  }
}

/* The explicit dark choice, so a toggle wins in both directions. The same values again. */
:root[data-theme="dark"] {
  --colorNeutralBackground1: #1f1f1f;
  --colorNeutralBackground2: #2c2c2c;
  --colorNeutralStroke1: #404040;
  --colorNeutralStroke2: #333333;
  --colorNeutralForeground1: #ffffff;
  --colorNeutralForeground2: #ababab;
  --colorBrandBackground: #479ef5;
  --colorBrandStroke1: #479ef5;
  --colorNeutralForegroundOnBrand: #000000;
  --colorPaletteGreenBackground2: #052505;
  --colorPaletteGreenForeground2: #54b054;
  --colorPaletteYellowBackground2: #2c2200;
  --colorPaletteYellowForeground2: #fce100;
  --colorPaletteRedBackground2: #3b0509;
  --colorPaletteRedForeground2: #f1707b;
}
```

The five tokens with no override row keep their `:root` values, which is what the audit above
measured. Adding an override for them changes the spec, not the CSS shape.

Paint the canvas from `--colorNeutralBackground1` explicitly. A transparent surface borrows the host
page's colour, and then every ratio in this audit is measured against something else.

---

## The specification, as supplied

## Fluent2 Flowchart Design Spec
**Version:** 1.0.0
**Status:** Handoff-Ready
**Target:** Claude Code / Component Implementation

---

### 1. Design Tokens

#### 1.1 Color Tokens

| Token | Value | Usage |
|---|---|---|
| `colorNeutralBackground1` | `#ffffff` | Default shape fill |
| `colorNeutralBackground2` | `#f5f5f5` | Alternate / hover fill |
| `colorNeutralStroke1` | `#d1d1d1` | Default shape border |
| `colorNeutralStroke2` | `#e0e0e0` | Subtle border variant |
| `colorBrandBackground` | `#0f6cbd` | Brand / primary fill |
| `colorBrandBackgroundHover` | `#115ea3` | Brand hover fill |
| `colorBrandStroke1` | `#0f6cbd` | Brand border |
| `colorPaletteGreenBackground2` | `#e6f4ea` | Checks-pass success fill |
| `colorPaletteGreenForeground2` | `#107c10` | Checks-pass success icon/text |
| `colorPaletteGreenBorderActive` | `#107c10` | Checks-pass success border |
| `colorPaletteRedBackground2` | `#fde7e9` | Checks-fail / error fill |
| `colorPaletteRedForeground2` | `#c50f1f` | Checks-fail error icon/text |
| `colorPaletteRedBorderActive` | `#c50f1f` | Checks-fail error border |
| `colorPaletteYellowBackground2` | `#fff4ce` | Checks-warning fill |
| `colorPaletteYellowForeground2` | `#835b00` | Checks-warning icon/text |
| `colorPaletteYellowBorderActive` | `#835b00` | Checks-warning border |
| `colorNeutralForeground1` | `#242424` | Primary label text |
| `colorNeutralForeground2` | `#616161` | Secondary / sublabel text |
| `colorNeutralForegroundOnBrand` | `#ffffff` | Label on brand fill |
| `colorNeutralForegroundDisabled` | `#bdbdbd` | Disabled state text |

#### 1.2 Typography Tokens

| Token | Value | Usage |
|---|---|---|
| `fontFamilyBase` | `'Segoe UI', system-ui, sans-serif` | All shape labels |
| `fontSizeBase200` | `12px` | Sublabel / annotation text |
| `fontSizeBase300` | `14px` | Primary shape label |
| `fontSizeBase400` | `16px` | Emphasis / header label |
| `fontWeightRegular` | `400` | Default label weight |
| `fontWeightSemibold` | `600` | Emphasis label weight |
| `lineHeightBase200` | `16px` | Sublabel line height |
| `lineHeightBase300` | `20px` | Primary label line height |

#### 1.3 Spacing & Geometry Tokens

| Token | Value | Usage |
|---|---|---|
| `spacingHorizontalS` | `8px` | Inner padding horizontal |
| `spacingHorizontalM` | `12px` | Standard inner padding |
| `spacingHorizontalL` | `16px` | Wide inner padding |
| `spacingVerticalS` | `8px` | Inner padding vertical |
| `spacingVerticalM` | `12px` | Standard vertical padding |
| `borderRadiusNone` | `0px` | Sharp-cornered shapes |
| `borderRadiusSmall` | `2px` | Subtle rounding |
| `borderRadiusMedium` | `4px` | Standard rounding |
| `borderRadiusCircular` | `50%` | Fully circular shapes |
| `strokeWidthThin` | `1px` | Default border weight |
| `strokeWidthThick` | `2px` | Selected / emphasis border |
| `strokeWidthThicker` | `3px` | Active / focused border |

#### 1.4 Shadow & Elevation Tokens

| Token | Value | Usage |
|---|---|---|
| `shadow2` | `0 1px 2px rgba(0,0,0,0.14)` | Resting card elevation |
| `shadow4` | `0 2px 4px rgba(0,0,0,0.14)` | Hover elevation |
| `shadow8` | `0 4px 8px rgba(0,0,0,0.14)` | Selected elevation |
| `shadow16` | `0 8px 16px rgba(0,0,0,0.14)` | Dragging elevation |

---

### 2. Shared Shape Anatomy

All flowchart shapes share this base structure: an optional 16x16 icon, a primary
label, and an optional sublabel beneath it.

**Base dimensions:**
- Default width: `160px` (min) to `320px` (max)
- Default height: `48px` (single-line), auto-expands with content
- Icon size: `16x16px` Fluent System Icons (regular weight by default)
- Label padding: `spacingHorizontalM` by `spacingVerticalS`
- Icon-to-label gap: `spacingHorizontalS`

**Interaction states for all shapes:**

| State | Border | Fill | Shadow | Cursor |
|---|---|---|---|---|
| Default | `colorNeutralStroke1` `1px` | `colorNeutralBackground1` | `shadow2` | `default` |
| Hover | `colorNeutralStroke1` `1px` | `colorNeutralBackground2` | `shadow4` | `pointer` |
| Selected | `colorBrandStroke1` `2px` | `colorNeutralBackground1` | `shadow8` | `default` |
| Dragging | `colorBrandStroke1` `2px` | `colorNeutralBackground1` | `shadow16` | `grabbing` |
| Disabled | `colorNeutralStroke2` `1px` | `colorNeutralBackground2` | none | `not-allowed` |

---

### 3. Shape Definitions

#### 3.1 Process (Rectangle)

**Purpose:** A standard step or action in the flow.

**Geometry:** rectangle, `borderRadiusMedium` (4px), width 160-320px, height 48px or more.

**Tokens:**
- Fill: `colorNeutralBackground1`
- Border: `colorNeutralStroke1`, `strokeWidthThin`
- Border-radius: `borderRadiusMedium`
- Label: `colorNeutralForeground1`, `fontSizeBase300`, `fontWeightSemibold`
- Sublabel: `colorNeutralForeground2`, `fontSizeBase200`, `fontWeightRegular`
- Icon: Fluent `TaskListSquare16Regular` or contextual

**Variants:**

| Variant | Fill | Border | Label color |
|---|---|---|---|
| Default | `colorNeutralBackground1` | `colorNeutralStroke1` | `colorNeutralForeground1` |
| Brand | `colorBrandBackground` | `colorBrandStroke1` | `colorNeutralForegroundOnBrand` |
| Subtle | `colorNeutralBackground2` | `colorNeutralStroke2` | `colorNeutralForeground1` |

---

#### 3.2 Decision (Diamond)

**Purpose:** A branching point with two or more conditional paths.

**Geometry:** width `160px`, height `80px`, rendered as a diamond via a rotated
wrapper or a native SVG polygon. The inner label container is counter-rotated.
Exits: top, right, bottom, left. Exit labels "Yes" / "No" or custom.

**Tokens:**
- Fill: `colorNeutralBackground1`
- Border: `colorNeutralStroke1`, `strokeWidthThin`
- Label: `colorNeutralForeground1`, `fontSizeBase300`, `fontWeightSemibold`, centered
- Exit label: `colorNeutralForeground2`, `fontSizeBase200`, at the midpoint of each exit edge
- Icon: Fluent `QuestionCircle16Regular`

**Exit label placement:**

| Exit | Position offset |
|---|---|
| Right (Yes) | `+8px` from right vertex, centered vertically |
| Bottom (No) | `+8px` from bottom vertex, centered horizontally |
| Left | `+8px` from left vertex, centered vertically |
| Top | `+8px` from top vertex, centered horizontally |

---

#### 3.3 Terminator (Stadium / Pill)

**Purpose:** Start or End of a flow.

**Tokens:**

| Role | Fill | Border | Label |
|---|---|---|---|
| Start | `colorBrandBackground` | `colorBrandStroke1` | `colorNeutralForegroundOnBrand` |
| End | `colorNeutralBackground1` | `colorNeutralStroke1` `strokeWidthThick` | `colorNeutralForeground1` |

- Border-radius: full pill, `border-radius: 9999px`
- Height: `40px`
- Icon (Start): Fluent `Play16Filled`, `colorNeutralForegroundOnBrand`
- Icon (End): Fluent `RecordStop16Regular`, `colorNeutralForeground1`

---

#### 3.4 Data / Input-Output (Parallelogram)

**Purpose:** Represents data entering or leaving the process.

**Geometry:** parallelogram, 15 degree skew. Rendered via `transform: skewX(-15deg)`
on the wrapper with the inner content counter-skewed, or a native SVG polygon.

**Tokens:**
- Fill: `colorNeutralBackground1`
- Border: `colorNeutralStroke1`, `strokeWidthThin`
- Label: `colorNeutralForeground1`, `fontSizeBase300`, `fontWeightSemibold`
- Icon: Fluent `DataUsage16Regular`

---

#### 3.5 Predefined Process (Rectangle with double vertical stripes)

**Purpose:** A named subprocess or subroutine defined elsewhere.

**Geometry:** outer rectangle at `borderRadiusMedium`, with `8px`-wide vertical bars
flush to the left and right inner edges in the same border color.

**Tokens:**
- Fill: `colorNeutralBackground1`
- Stripe fill: `colorNeutralBackground2`
- Border: `colorNeutralStroke1`, `strokeWidthThin`
- Label: `colorNeutralForeground1`, `fontSizeBase300`, `fontWeightSemibold`
- Icon: Fluent `SubtractSquare16Regular`

---

#### 3.6 Document (Rectangle with wavy bottom)

**Purpose:** Output that is a document or printed report.

**Geometry:** top corners at `borderRadiusMedium`; bottom edge is an SVG sine wave,
amplitude 4px, period 16px. Height `56px`, the extra 8px carrying the wave.

**Tokens:**
- Fill: `colorNeutralBackground1`
- Border (top and sides): `colorNeutralStroke1`, `strokeWidthThin`
- Wave stroke: `colorNeutralStroke1`, `strokeWidthThin`; wave fill matches shape fill
- Label: `colorNeutralForeground1`, `fontSizeBase300`, `fontWeightSemibold`
- Icon: Fluent `Document16Regular`

---

#### 3.7 Manual Operation (Trapezoid)

**Purpose:** A step requiring human intervention.

**Geometry:** top edge full width, bottom edge inset 16px each side. Rendered via an
SVG polygon or `clip-path: polygon(0 0, 100% 0, calc(100% - 16px) 100%, 16px 100%)`.

**Tokens:**
- Fill: `colorNeutralBackground1`
- Border: `colorNeutralStroke1`, `strokeWidthThin`
- Label: `colorNeutralForeground1`, `fontSizeBase300`, `fontWeightSemibold`
- Icon: Fluent `Person16Regular`

---

#### 3.8 Delay (D-shape / half-pill)

**Purpose:** A waiting or delay step.

**Geometry:** `border-radius: 0 9999px 9999px 0`, width `160px`, height `48px`.
The right side is a full semicircle; the left side is a straight vertical edge.

**Tokens:**
- Fill: `colorNeutralBackground1`
- Border: `colorNeutralStroke1`, `strokeWidthThin`
- Label: `colorNeutralForeground1`, `fontSizeBase300`, `fontWeightSemibold`
- Icon: Fluent `Timer16Regular`

---

#### 3.9 Connector (Circle / off-page reference)

**Purpose:** Links flow across page breaks or distant areas.

**Geometry:** perfect circle, width = height = `40px`, `borderRadiusCircular`, with a
single letter or number centered inside.

**Tokens:**
- Fill: `colorNeutralBackground1`
- Border: `colorNeutralStroke1`, `strokeWidthThick`
- Label: `colorNeutralForeground1`, `fontSizeBase400`, `fontWeightSemibold`, centered
- No icon; the label is the identifier

---

### 4. Checks-Pass Shape Variants

Checks-pass shapes are status-bearing versions of the Process rectangle, used to
surface pass, warning and fail states inline in a flow.

#### 4.1 Checks-Pass: Success

**When to use:** All validation checks passed; flow proceeds.

**Tokens:**
- Fill: `colorPaletteGreenBackground2` (`#e6f4ea`)
- Border: `colorPaletteGreenBorderActive` (`#107c10`), `strokeWidthThick`
- Icon: Fluent `CheckmarkCircle16Filled`, color `colorPaletteGreenForeground2`
- Label: `colorPaletteGreenForeground2` (`#107c10`), `fontSizeBase300`, `fontWeightSemibold`
- Sublabel: `colorPaletteGreenForeground2` at `80%` opacity, `fontSizeBase200`

---

#### 4.2 Checks-Pass: Warning

**When to use:** Some checks passed with caveats; flow may proceed with acknowledgment.

**Tokens:**
- Fill: `colorPaletteYellowBackground2` (`#fff4ce`)
- Border: `colorPaletteYellowBorderActive` (`#835b00`), `strokeWidthThick`
- Icon: Fluent `Warning16Filled`, color `colorPaletteYellowForeground2`
- Label: `colorPaletteYellowForeground2` (`#835b00`), `fontSizeBase300`, `fontWeightSemibold`
- Sublabel: `colorPaletteYellowForeground2` at `80%` opacity, `fontSizeBase200`

---

#### 4.3 Checks-Pass: Fail

**When to use:** One or more checks failed; flow is blocked.

**Tokens:**
- Fill: `colorPaletteRedBackground2` (`#fde7e9`)
- Border: `colorPaletteRedBorderActive` (`#c50f1f`), `strokeWidthThick`
- Icon: Fluent `DismissCircle16Filled`, color `colorPaletteRedForeground2`
- Label: `colorPaletteRedForeground2` (`#c50f1f`), `fontSizeBase300`, `fontWeightSemibold`
- Sublabel: `colorPaletteRedForeground2` at `80%` opacity, `fontSizeBase200`

---

### 5. Arrow / Connector Styles

#### 5.1 Token mapping

| Token | Value | Usage |
|---|---|---|
| `colorNeutralStroke1` | `#d1d1d1` | Default connector line |
| `colorBrandStroke1` | `#0f6cbd` | Highlighted / active connector |
| `colorPaletteGreenBorderActive` | `#107c10` | Success path connector |
| `colorPaletteRedBorderActive` | `#c50f1f` | Failure path connector |
| `strokeWidthThin` | `1px` | Default line weight |
| `strokeWidthThick` | `2px` | Selected / emphasis line weight |
| `fontSizeBase200` | `12px` | Edge label text |
| `colorNeutralForeground2` | `#616161` | Edge label text color |

#### 5.2 Arrow types

| Style | Description | CSS / SVG |
|---|---|---|
| Solid | Standard sequential flow | `stroke-dasharray: none` |
| Dashed | Optional or conditional path | `stroke-dasharray: 6 4` |
| Dotted | Reference or annotation link | `stroke-dasharray: 2 4` |

#### 5.3 Arrowhead styles

| Style | Usage | SVG marker |
|---|---|---|
| Filled triangle (default) | Standard directional flow | `<marker orient="auto" markerWidth="8" markerHeight="8"><path d="M0,0 L8,4 L0,8 Z" fill="currentColor"/>` |
| Open chevron | Weak or reference flow | `<marker><path d="M0,0 L8,4 L0,8" fill="none" stroke="currentColor"/>` |
| Circle dot | Event trigger start | `<marker><circle cx="4" cy="4" r="3"/>` |

#### 5.4 Routing rules

- Orthogonal (default): all connectors route at 90 degree angles with `8px` corner radius on bends.
- Straight: direct point-to-point, used only when shapes are axis-aligned with no obstacles.
- Exit priority by shape type:

| Shape | Primary exit | Secondary exit |
|---|---|---|
| Process | Bottom center | Right center |
| Decision | Right (Yes) | Bottom (No) |
| Terminator (Start) | Bottom center | none |
| Terminator (End) | Top center (entry only) | none |
| Data / I-O | Bottom center | Right center |
| Connector (circle) | Bottom center | Right center |

#### 5.5 Edge label spec

- Font: `fontFamilyBase`, `fontSizeBase200`, `fontWeightRegular`
- Color: `colorNeutralForeground2`
- Background: `colorNeutralBackground1` with `2px` horizontal padding
- Placement: midpoint of edge, `8px` above the line, or beside it for vertical edges
- Max width: `80px` before wrapping

---

### 6. Dark Mode Token Overrides

Apply these overrides when `[data-theme="dark"]` or `prefers-color-scheme: dark`:

| Light token | Dark value |
|---|---|
| `colorNeutralBackground1` | `#1f1f1f` |
| `colorNeutralBackground2` | `#2c2c2c` |
| `colorNeutralStroke1` | `#404040` |
| `colorNeutralStroke2` | `#333333` |
| `colorNeutralForeground1` | `#ffffff` |
| `colorNeutralForeground2` | `#ababab` |
| `colorBrandBackground` | `#479ef5` |
| `colorBrandStroke1` | `#479ef5` |
| `colorNeutralForegroundOnBrand` | `#000000` |
| `colorPaletteGreenBackground2` | `#052505` |
| `colorPaletteGreenForeground2` | `#54b054` |
| `colorPaletteYellowBackground2` | `#2c2200` |
| `colorPaletteYellowForeground2` | `#fce100` |
| `colorPaletteRedBackground2` | `#3b0509` |
| `colorPaletteRedForeground2` | `#f1707b` |

---

### 7. Accessibility Requirements

- Contrast: all label and background combinations must meet WCAG AA, 4.5:1 for normal text and 3:1 for large text at 18pt or above.
- Focus ring: `strokeWidthThicker` (`3px`) outline, `colorBrandStroke1`, `2px` offset, on all interactive shapes.
- Keyboard: all shapes selectable via Tab; move with arrow keys; connect via Enter, then target, then Enter.
- ARIA: each shape exposes `role="figure"` with an `aria-label` combining shape type and label text, for example "Decision: Is user authenticated?".
- Screen reader announcements: state changes (selected, connected, error) announced via an `aria-live="polite"` region.

---

### 8. Component API Surface (Reference)

```ts
interface FlowchartShapeProps {
  type:
    | 'process'
    | 'decision'
    | 'terminator'
    | 'data'
    | 'predefined-process'
    | 'document'
    | 'manual-operation'
    | 'delay'
    | 'connector'
    | 'checks-pass';

  label: string;
  sublabel?: string;

  /** For type === 'terminator' */
  role?: 'start' | 'end';

  /** For type === 'connector' */
  identifier?: string;

  /** For type === 'checks-pass' */
  status?: 'success' | 'warning' | 'fail';

  /** Visual variant for 'process' shapes */
  variant?: 'default' | 'brand' | 'subtle';

  /** Fluent System Icon name (16px Regular) */
  icon?: string;

  selected?: boolean;
  disabled?: boolean;

  width?: number;   // px, default 160
  height?: number;  // px, default 48

  onSelect?: () => void;
  onConnect?: (sourcePort: Port) => void;
}

type Port = 'top' | 'right' | 'bottom' | 'left';

interface FlowchartEdgeProps {
  sourceId: string;
  targetId: string;
  sourcePort?: Port;
  targetPort?: Port;
  label?: string;
  style?: 'solid' | 'dashed' | 'dotted';
  arrowhead?: 'filled' | 'open' | 'dot';
  variant?: 'default' | 'brand' | 'success' | 'error';
  selected?: boolean;
}
```

---

### 9. Shape Quick-Reference Table

| Shape | Type key | Geometry | Primary icon |
|---|---|---|---|
| Process | `process` | Rectangle, r=4px | `TaskListSquare16Regular` |
| Decision | `decision` | Diamond / rotated square | `QuestionCircle16Regular` |
| Terminator Start | `terminator` + `role="start"` | Full-pill, brand fill | `Play16Filled` |
| Terminator End | `terminator` + `role="end"` | Full-pill, neutral | `RecordStop16Regular` |
| Data / I-O | `data` | Parallelogram 15 degree skew | `DataUsage16Regular` |
| Predefined Process | `predefined-process` | Rectangle with side stripes | `SubtractSquare16Regular` |
| Document | `document` | Rectangle with wavy bottom | `Document16Regular` |
| Manual Operation | `manual-operation` | Trapezoid, top wide | `Person16Regular` |
| Delay | `delay` | D-shape, half-pill right | `Timer16Regular` |
| Connector | `connector` | Circle 40px | the identifier character |
| Checks-Pass success | `checks-pass` + `status="success"` | Rectangle, green | `CheckmarkCircle16Filled` |
| Checks-Pass warning | `checks-pass` + `status="warning"` | Rectangle, yellow | `Warning16Filled` |
| Checks-Pass fail | `checks-pass` + `status="fail"` | Rectangle, red | `DismissCircle16Filled` |
