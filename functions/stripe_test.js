const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
if (!stripeSecretKey) {
  throw new Error('Missing STRIPE_SECRET_KEY environment variable.');
}
const stripe = require('stripe')(stripeSecretKey);

async function runTests() {
  console.log('=== Iniciando Pruebas de Pagos (Stripe Backend) ===\n');

  try {
    console.log('1. Probando creación de cuenta Connect para Cuidador...');
    const account = await stripe.accounts.create({
      type: 'express',
      country: 'ES',
      email: 'test_cuidador_stripe@senicare.app',
      capabilities: {
        card_payments: { requested: true },
        transfers: { requested: true }
      },
      business_type: 'individual'
    });
    console.log(`✅ Cuenta Connect creada con éxito. Account ID: ${account.id}`);

    console.log('\n2. Probando generación de Link de Onboarding (Account Link)...');
    const accountLink = await stripe.accountLinks.create({
      account: account.id,
      refresh_url: 'https://senicare.app/reauth',
      return_url: 'https://senicare.app/return',
      type: 'account_onboarding',
    });
    console.log(`✅ Link generado correctamente. URL: ${accountLink.url}`);

    console.log('\n3. Probando creación de Payment Intent (Reserva de Cliente)...');
    // Simular un pago de 50 EUR
    const paymentIntent = await stripe.paymentIntents.create({
      amount: 5000, // 50.00 EUR
      currency: 'eur',
      payment_method_types: ['card'],
      transfer_group: `booking_test_${Date.now()}`
    });
    console.log(`✅ Payment Intent creado. Client Secret: ${paymentIntent.client_secret.substring(0, 20)}...`);
    console.log(`   Transfer Group: ${paymentIntent.transfer_group}`);

    // Nota: Confirmar un pago requiere un payment_method (tarjeta de test).
    // Podemos crear uno para testear si se confirma el pago y luego testear transfer
    console.log('\n4. Simulando pago exitoso (confirmando con tarjeta test de Stripe)...');
    const confirmedIntent = await stripe.paymentIntents.confirm(paymentIntent.id, {
      payment_method: 'pm_card_visa', // Tarjeta de prueba de Stripe
    });
    console.log(`✅ Payment Intent confirmado. Estado: ${confirmedIntent.status}`);

    console.log('\n5. Probando Transferencia al Cuidador (Escrow Release)...');
    // Para probar la transferencia, la cuenta Connect debe poder recibir transferencias.
    // Stripe test mode permite transfers sin completar onboarding para express accounts.
    const transfer = await stripe.transfers.create({
      amount: 4000, // 40.00 EUR (Asumiendo 10 EUR de comisión)
      currency: 'eur',
      destination: account.id,
      transfer_group: paymentIntent.transfer_group,
    });
    console.log(`✅ Transferencia creada. Transfer ID: ${transfer.id}`);

    console.log('\n=== Todas las pruebas de backend de Stripe pasaron correctamente ===');
  } catch (error) {
    console.error('\n❌ Error durante las pruebas de Stripe:');
    console.error(error.message);
  }
}

runTests();
