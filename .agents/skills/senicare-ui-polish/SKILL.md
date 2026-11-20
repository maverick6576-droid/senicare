---
name: senicare-ui-polish
description: >-
  Use this skill to elevate the visual interface, design system consistency,
  accessibility, responsiveness, and tactile polish of SeniCare screens and
  widgets across mobile and web.
---

# SeniCare Visual Interface & UI Polish Runbook

Make SeniCare look and feel like a top-tier, warm, trustworthy care platform — effortless for stressed families and comfortable for older adults.

## 1. Visual Identity & Design System (`lib/core/theme.dart`)

- **Palette discipline**: Use warm, reassuring, high-trust tones (soft warm neutrals for surfaces, calm deep teal/navy for primary actions, warm amber/coral sparingly for attention, emerald for verified/safe states, crimson only for destructive/emergency actions). Avoid harsh pure `#000000` on `#FFFFFF` or neon/gimmicky gradients.
- **Single source of truth**: Every color, radius, elevation, and text style must come from `Theme.of(context).colorScheme` and `Theme.of(context).textTheme` (defined in `lib/core/theme.dart`), never magic hardcoded hex colors scattered across screens.
- **Spacing rhythm**: Use a strict 4/8dp spacing grid (`8`, `12`, `16`, `24`, `32`) and consistent card border radii (`16`–`20dp`) with subtle borders or soft low-elevation shadows.

## 2. Accessibility & Senior-Friendly Ergonomics (Non-Negotiable)

- **Contrast**: Minimum **4.5:1** (WCAG AA) for all body text and **7:1** (AAA) on primary senior-facing flows; ≥ 3:1 for icons and input borders.
- **Touch targets**: Minimum **48×48dp** on every interactive control; **52–56dp** height for primary CTAs (`ElevatedButton` / `FilledButton`).
- **Typography**: Body text ≥ **16sp** with generous line height (`1.4–1.5`). Test at `TextScaler.linear(1.5)` and `2.0` — zero `RenderFlex overflowed` clipping. Wrap row text in `Expanded`/`Flexible` with graceful wrapping instead of truncating crucial labels.
- **Icons + Labels**: Never use ambiguous icon-only buttons for key actions (Book, Call, SOS, Pay, Chat); pair icons with crisp 1–2 word labels.
- **Delegate a11y checks**: Invoke `flutter_a11y_agent` on modified screens to verify `Semantics`, screen reader traversal, and contrast.

## 3. Polish Checklist for Every Screen (`lib/screens/`)

For each screen, verify all 5 UI states exist and look intentional:
1. **Loading**: Structured `Shimmer` skeletons matching final layout (not jarring full-screen white spinners).
2. **Populated**: Clear visual hierarchy (1 dominant CTA per viewport), crisp avatars via `CachedNetworkImage`, subtle status pills (`Verificada`, `Disponible`, `En curso`).
3. **Empty**: Empathetic illustration/icon + clear explanation + single next-step button.
4. **Error**: Human-readable message + immediate `Reintentar` button (never raw `FirebaseException` codes).
5. **Submitting**: Inline button spinner + disabled state to prevent double-taps + `HapticFeedback.lightImpact()` on key confirmations.

## 4. Visual Redesign & Verification Workflow

- For major screen redesigns, use **StitchMCP** (or **Mobbin** plugin if installed) to explore high-converting real-world mobile patterns before coding.
- Verify layout across compact mobile (360×800), large mobile (430×932), and Web viewports; fix any overflow immediately using `flutter-fix-layout-issues`.
- Check localization (`lib/l10n/`): zero hardcoded English/Spanish strings mixed inconsistently.
