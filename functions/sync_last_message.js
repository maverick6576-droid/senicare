const { onDocumentDeleted } = require("firebase-functions/v2/firestore");

exports.syncLastMessageOnDelete = onDocumentDeleted({
  document: "chats/{chatRoomId}/messages/{messageId}",
  region: "europe-west1"
}, async (event) => {
  const chatId = event.params.chatRoomId;
  const messagesRef = admin.firestore().collection(`chats/${chatId}/messages`);
  const lastMsgSnapshot = await messagesRef.orderBy('timestamp', 'desc').limit(1).get();
  
  if (lastMsgSnapshot.empty) {
    await admin.firestore().collection('chats').doc(chatId).update({
      lastMessage: '',
      lastMessageTimestamp: admin.firestore.FieldValue.serverTimestamp()
    });
  } else {
    const lastMsgData = lastMsgSnapshot.docs[0].data();
    await admin.firestore().collection('chats').doc(chatId).update({
      lastMessage: lastMsgData.text,
      lastMessageTimestamp: lastMsgData.timestamp
    });
  }
  return null;
});
