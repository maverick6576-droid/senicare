---
name: marketplace-business-strategist
description: Evaluates SeniCare's business plan, marketplace viability, unit economics (take-rate vs Stripe fees), disintermediation risk, Spanish regulatory/tax compliance, and 12/24/36-month profit projections.
---

# Marketplace Business Strategist — SeniCare (Grandpa Care)

Use this skill to evaluate the commercial viability, unit economics, competitive moat, regulatory posture, and future profitability of **SeniCare** (an elder-care two-sided marketplace operating in Spain).

## Core Evaluation Framework

### 1. Unit Economics & Net Margin per Booking
Always extract the **exact pricing and fee parameters from the codebase** (`functions/index.js` and `lib/repositories/firebase/firestore_stats_repository.dart`) before modeling:
- **Hourly gross rate**: Typical market range in Spain (12€–20€/h, median ~15€/h).
- **Client fee**: Platform service fee charged to families (e.g., 3%).
- **Caregiver commission tiers**: Loyalty tiers (e.g., 1–20h: 18%, 21–80h: 12%, >80h: 6%) and urgency bonus discount (up to -10 percentage points).
- **Payment processing costs (Stripe Spain/EEA)**:
  - Standard EEA card: ~1.5% + 0.25€
  - Non-EEA / commercial card: ~2.9% + 0.25€
  - SEPA Direct Debit: ~0.8% (capped)
  - Stripe Connect Express active account & payout fees (monthly active account fee + payout percentage if applicable).
- **Net Contribution Margin per Hour / Booking**:
  - `Gross Platform Revenue = Client Fee + Caregiver Commission`
  - `Net Revenue = Gross Platform Revenue - Stripe Processing Fees - Expected Chargeback/Dispute Loss (0.5%–1.5%)`
  - Explicitly test edge cases: e.g., when a loyal caregiver (>80h, 6% commission) takes an urgent shift (-10% bonus -> 0% caregiver commission) or short 1-hour shifts!

### 2. Marketplace Viability & Disintermediation Risk
- **Leakage / Disintermediation**: Elder care has high repeat frequency with the *same* caregiver. Evaluate whether SeniCare's loyalty commission drop (`18% -> 12% -> 6%`) + escrow protection + care journal + invoicing + insurance/trust is strong enough to stop families and caregivers from moving to WhatsApp/cash after booking #1.
- **Liquidity & Cold-Start Problem**: Two-sided hyperlocal marketplaces (by neighborhood/city) fail if launched nationwide at once. Recommend geographic beachhead strategy (1–2 postal codes / cities).
- **CAC vs. LTV**: Estimate realistic Family CAC (paid search/Meta/local partnerships: 35€–90€) and Caregiver CAC (20€–50€) vs. 12-month LTV.

### 3. Regulatory & Legal Viability in Spain
- **Labor classification**: Intermediary marketplace vs. employer (Ley Rider / Estatuto de los Trabajadores / Empleadas del Hogar — Régimen Especial). Caregivers must set their own rates and schedules; SeniCare must avoid acting as an employer.
- **RGPD Art. 9 (Special Category Health Data)**: Patient health notes require explicit consent, DPO/EIPD (Evaluación de Impacto), and strict access minimization.
- **DAC7 & Fiscal Compliance**: EU DAC7 reporting obligations for digital platforms facilitating personal services, plus VAT (IVA 21%) on SeniCare's platform commission invoices.
- **Civil Liability Insurance**: Families expect a liability/accident policy covering home visits.

### 4. Future Profit Projections (12, 24, 36 Months)
Build 3 concrete scenarios (**Conservative**, **Base**, **Optimistic**) with transparent assumptions:
- Active families, average hours/month per family, GMV (Gross Merchandise Volume), blended take-rate, Stripe + Firebase/cloud + support/KYC + marketing fixed/variable costs, and **Monthly EBITDA / Break-even point**.

## Output Standard
Be candid, data-driven, and concrete. Highlight both **strengths** and **fatal business risks** with actionable mitigations.
