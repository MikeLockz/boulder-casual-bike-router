# Project Wayfinder: PRD & Design Brief

## 1. Project Overview
Wayfinder is a premium mobile navigation application designed for explorers and commuters who value a sophisticated, high-legibility interface. The app provides seamless route planning, active navigation guidance, and historical route management, all wrapped in a custom "Mint Dark" visual identity.

## 2. Design System: Mint Dark
The application utilizes a cohesive dark-themed design system characterized by:
- **Color Palette**: Deep charcoal and forest greens (`#121414`, `#0d0f0f`) as base surfaces, with vibrant "Mint Glow" (`#00a98f`) for primary actions, active states, and highlights.
- **Typography**: Inter (Sans-serif) for high legibility across all lighting conditions.
- **Visual Style**: Modern, flat aesthetic with subtle elevation, rounded corners (8px), and high-contrast iconography.

## 3. Core Features & Screen Flows

### A. Discovery & Entry
- **Landing View (Map & Search)**: The initial entry point featuring a full-screen immersive dark map. A central "Where to?" search bar allows for immediate intent entry.
- **Main Navigation (Drawer)**: A slide-in menu for high-level navigation, including user profile (Pro Member status), Saved Places, and app settings.

### B. Planning Mode
- **Search & Destinations**: When search is activated, users can select from "Saved Locations" (Home, Work) or browse nearby results (e.g., Parks).
- **Route Overview**: A pre-trip summary showing duration (e.g., "12 min"), distance, ETA, and a "Start Navigation" primary action.

### C. Navigation Mode
- **Active Guidance**: A zoomed-in map view with a high-contrast instruction card (e.g., "Turn Right on 9th St").
- **Real-time Stats**: Bottom persistent bar showing remaining time, distance, and a prominent "End" button for safety.

### D. User Management & History
- **Past Routes**: A visual log of previous adventures, showing route previews, duration, and distance.
- **User Settings**: Comprehensive control over navigation preferences (Avoid Tolls, Avoid Highways) and account security.

## 4. Technical Specifications
- **Platform**: Mobile (iOS/Android optimized).
- **Navigation Logic**: Standardized 4-tab bottom navigation (Plan, Routes, History, Settings) across all primary views.
- **Contextual UI**: Dynamic switching between planning and active guidance states.
