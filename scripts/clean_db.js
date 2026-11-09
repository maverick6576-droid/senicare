const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');

// Ensure you run this inside Cloud Shell with:
// npm install firebase-admin
// node scripts/clean_db.js

initializeApp({
  credential: applicationDefault(),
  projectId: 'senicare-3342d'
});

const db = getFirestore();
const auth = getAuth();

const KEEPS = [
  'maverick6576@gmail.com'
];
const KEEP_ID_PREFIX = 'mock_cg_';

async function clean() {
  console.log('Fetching all auth users...');
  
  let nextPageToken;
  const usersToDelete = [];
  const keepUids = new Set();
  
  do {
    const listUsersResult = await auth.listUsers(1000, nextPageToken);
    listUsersResult.users.forEach((userRecord) => {
      const isMockCg = userRecord.uid.startsWith(KEEP_ID_PREFIX);
      const isOwner = KEEPS.includes(userRecord.email);
      
      if (isMockCg || isOwner) {
        keepUids.add(userRecord.uid);
        console.log(`Keeping user: ${userRecord.email || userRecord.uid}`);
      } else {
        usersToDelete.push(userRecord.uid);
      }
    });
    nextPageToken = listUsersResult.pageToken;
  } while (nextPageToken);

  console.log(`Found ${usersToDelete.length} users to delete from Auth.`);
  
  if (usersToDelete.length > 0) {
    await auth.deleteUsers(usersToDelete);
    console.log('Deleted users from Auth.');
  }

  // Delete from Firestore collections
  const collections = ['users', 'clients', 'caregivers'];
  
  for (const coll of collections) {
    console.log(`Cleaning collection: ${coll}...`);
    const snapshot = await db.collection(coll).get();
    let deletedCount = 0;
    
    const batch = db.batch();
    snapshot.forEach(doc => {
      const isMockCg = doc.id.startsWith(KEEP_ID_PREFIX);
      if (!keepUids.has(doc.id) && !isMockCg) {
        batch.delete(doc.ref);
        deletedCount++;
      } else {
        console.log(`Keeping doc: ${coll}/${doc.id}`);
      }
    });
    
    if (deletedCount > 0) {
      await batch.commit();
      console.log(`Deleted ${deletedCount} documents from ${coll}.`);
    } else {
      console.log(`Nothing to delete in ${coll}.`);
    }
  }

  console.log('Database cleanup complete!');
}

clean().catch(console.error);
