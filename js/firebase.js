import { initializeApp } from "https://www.gstatic.com/firebasejs/12.2.1/firebase-app.js";

import {
  getAuth,
  GoogleAuthProvider
} from "https://www.gstatic.com/firebasejs/12.2.1/firebase-auth.js";

const firebaseConfig = {
  apiKey: "AIzaSyBg4cQtRuPikmQ6ft7c40oCpsLTPSN7xyw",
  authDomain: "alkber-f976b.firebaseapp.com",
  projectId: "alkber-f976b",
  storageBucket: "alkber-f976b.firebasestorage.app",
  messagingSenderId: "491266319328",
  appId: "1:491266319328:web:a1518a8e0ba5db40694185",
  measurementId: "G-JCBDJ66FMB"
};

const app = initializeApp(firebaseConfig);

const auth = getAuth(app);

const googleProvider = new GoogleAuthProvider();

export {
  app,
  auth,
  googleProvider
};
