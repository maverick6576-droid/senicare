/* Service Worker para notificaciones push web (FCM) de SeniCare. */
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

self.addEventListener('push', function (event) {
  if (!event.data) return;
  try {
    const payload = event.data.json();
    const title = payload?.notification?.title || 'SeniCare';
    const options = {
      body: payload?.notification?.body || 'Tienes una nueva actualización en SeniCare.',
      icon: 'icons/Icon-192.png',
      data: payload?.data || {},
    };
    event.waitUntil(self.registration.showNotification(title, options));
  } catch (_) {}
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clientList) {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow('/');
    })
  );
});
