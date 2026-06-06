---
name: Mint Dark
colors:
  surface: '#121414'
  surface-dim: '#121414'
  surface-bright: '#383939'
  surface-container-lowest: '#0d0f0f'
  surface-container-low: '#1a1c1c'
  surface-container: '#1e2020'
  surface-container-high: '#282a2a'
  surface-container-highest: '#333535'
  on-surface: '#e2e2e2'
  on-surface-variant: '#bbcac4'
  inverse-surface: '#e2e2e2'
  inverse-on-surface: '#2f3131'
  outline: '#86948f'
  outline-variant: '#3c4945'
  surface-tint: '#59dbbf'
  primary: '#59dbbf'
  on-primary: '#00382e'
  primary-container: '#00a98f'
  on-primary-container: '#00352c'
  inverse-primary: '#006b5a'
  secondary: '#8cd3d2'
  on-secondary: '#003737'
  secondary-container: '#005c5c'
  on-secondary-container: '#8bd2d2'
  tertiary: '#bacac5'
  on-tertiary: '#253330'
  tertiary-container: '#8a9995'
  on-tertiary-container: '#23312e'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#78f8db'
  primary-fixed-dim: '#59dbbf'
  on-primary-fixed: '#00201a'
  on-primary-fixed-variant: '#005143'
  secondary-fixed: '#a7efee'
  secondary-fixed-dim: '#8cd3d2'
  on-secondary-fixed: '#002020'
  on-secondary-fixed-variant: '#004f50'
  tertiary-fixed: '#d6e6e1'
  tertiary-fixed-dim: '#bacac5'
  on-tertiary-fixed: '#101e1b'
  on-tertiary-fixed-variant: '#3b4a46'
  background: '#121414'
  on-background: '#e2e2e2'
  surface-variant: '#333535'
  forest-deep: '#0A1F1F'
  surface-elevated: '#1C2121'
  mint-glow: '#26FFD4'
  success-teal: '#00CCAA'
  error-rose: '#FF5C5C'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
  headline-md:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  mono-data:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base-unit: 8px
  container-padding-mobile: 16px
  container-padding-desktop: 32px
  gutter: 24px
  stack-sm: 12px
  stack-md: 24px
  stack-lg: 48px
---

## Brand & Style

The design system is a sophisticated, high-performance interface tailored for modern finance and wealth management. It balances the stability of traditional banking with the agility of a fintech startup. The aesthetic is defined by "Deep Financial Tech"—a style that prioritizes data density, extreme legibility, and a sense of "quiet luxury."

The visual direction uses a **Corporate / Modern** framework infused with **Minimalism**. By leaning into a dark-mode-first approach, the system reduces eye strain for long-period financial monitoring while using vibrant mint accents to draw attention to growth and positive trends. Surfaces are treated with subtle depth to guide the user's focus through complex information architectures without clutter.

## Colors

The color palette is anchored by **Forest Deep**, a near-black green that provides more warmth and brand-alignment than a pure neutral gray. 

- **Primary:** The signature Mint Teal (#00A98F) is used for primary calls to action, active states, and positive financial indicators.
- **Secondary:** A muted Deep Teal (#1E6C6C) serves as a supporting color for secondary actions and structural borders.
- **Neutral:** Surfaces use a tiered system of dark greens. The base background is the darkest, while containers use slightly lighter "Surface Elevated" tones to create a sense of physical layering.
- **Accents:** High-brightness mint shades are reserved for data visualization and "glow" effects on high-priority alerts.

## Typography

This design system utilizes **Inter** for all roles, leveraging its exceptional legibility and extensive OpenType features. 

- **Numerical Data:** For financial tables and balances, always enable **tabular figures** (`tnum`) to ensure columns of numbers align vertically.
- **Hierarchy:** Use semi-bold (600) for headlines to create a strong visual anchor against the dark background. 
- **Scale:** On mobile, large display type should scale down to prevent excessive line wrapping, while body text remains consistent at 16px to ensure readability.
- **Labels:** Use the `label-sm` style for metadata and secondary headers, applying a slight letter spacing and uppercase transform for clear distinction from body text.

## Layout & Spacing

The layout follows a **Fixed-Fluid Hybrid** model. Content is centered within a maximum width of 1280px for desktop, while utilizing a fluid 12-column grid for internal layout components.

- **Grid:** Use a 24px gutter between columns to ensure financial data has "breathing room."
- **Rhythm:** All vertical spacing is a multiple of 8px. Use 12px (`stack-sm`) for related items in a list, and 48px (`stack-lg`) to separate major page sections.
- **Responsive Behavior:** At the 768px breakpoint (tablet), margins reduce to 24px. At the 480px breakpoint (mobile), margins reduce to 16px and the 12-column grid collapses to a 4-column structure.

## Elevation & Depth

In this design system, depth is communicated through **Tonal Layering** rather than heavy drop shadows. 

- **Surface Levels:** 
  - Level 0 (Background): #0A1F1F
  - Level 1 (Cards/Sidebar): #121414
  - Level 2 (Modals/Popovers): #1C2121
- **Subtle Definition:** Instead of traditional shadows, use 1px inner borders (strokes) with a low-opacity teal-white color (`rgba(233, 249, 244, 0.05)`). This creates a "glass-edge" effect that feels premium and precise.
- **Focus States:** Active elements may use a soft "Mint Glow"—an outer blur with 10% opacity of the primary teal color—to indicate focus without breaking the flat professional aesthetic.

## Shapes

The shape language is disciplined and geometric. A standard **8px (medium)** corner radius is used for the majority of UI components, including cards, buttons, and input fields.

- **Standard (8px):** Primary containers and buttons.
- **Large (16px):** Used sparingly for large hero sections or featured dashboard widgets.
- **Pill:** Reserved exclusively for tags, status indicators (e.g., "Paid," "Pending"), and chips to distinguish them from interactive buttons.

## Components

- **Buttons:** Primary buttons use a solid teal background with dark forest text. Secondary buttons use a transparent background with a 1px teal border.
- **Input Fields:** Dark backgrounds (#121414) with a subtle 1px border. On focus, the border transitions to primary teal with a soft 2px glow. Labels are positioned above the field using the `label-md` style.
- **Cards:** Use "Surface Level 1" with an 8px radius. Cards should not have shadows unless they are "floating" (e.g., modals). Use 24px internal padding for most dashboard cards.
- **Chips/Status Tags:** Utilize the pill shape. Use a low-opacity background of the status color (e.g., 10% green for "Success") with a high-contrast text color of the same hue.
- **Data Tables:** Remove vertical borders. Use 1px horizontal dividers in a muted teal-gray. Row height should be generous (min 48px) to maintain a premium feel.
- **Progress Bars:** Use a thick (8px) track with a rounded cap. The "filled" portion should use a gradient from Secondary Teal to Primary Mint to imply growth and momentum.