importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyA-4X5K5LOmoZfjCzqVbhdvLuB5Zbf9-IY',
  appId: '1:1010466683287:web:5c9acef15f54bcb7ee2cd2',
  messagingSenderId: '1010466683287',
  projectId: 'byaheroxperience',
  authDomain: 'byaheroxperience.firebaseapp.com',
  storageBucket: 'byaheroxperience.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((message) => {
  const notification = message.notification || {};
  const title = notification.title || 'ByaheroX Driver';
  const options = {
    body: notification.body || '',
    icon: '/icons/Icon-192.png',
  };

  self.registration.showNotification(title, options);
});
