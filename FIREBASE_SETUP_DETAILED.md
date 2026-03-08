# 🚀 Firebase Setup Guide for Smart Eat - Step by Step

## 📋 Prerequisites
- Google Account
- Flutter project ready (already done)
- Basic understanding of Firebase (optional)

---

## 🏗️ Step 1: Create Firebase Project

### 1.1 Go to Firebase Console
1. Open your web browser
2. Navigate to: https://console.firebase.google.com/
3. Sign in with your Google account

### 1.2 Create New Project
1. Click **"Create a project"** (or **"Add project"** if you have existing projects)
2. Enter project details:
   - **Project name**: `smart-eat-[your-name]` (e.g., `smart-eat-restaurant`)
   - **Project ID**: Auto-generated (or customize if preferred)
3. Check **"I accept the Firebase terms"**
4. Click **"Continue"**

### 1.3 Enable Google Analytics (Optional but Recommended)
1. Toggle **"Enable Google Analytics for this project"** → **ON**
2. Select or create a Google Analytics account
3. Choose **"Default Account for Firebase"** or create new
4. Click **"Create project"**

---

## 💰 Step 1.5: Choose Firebase Plan

### Available Plans:
1. **Spark Plan (Free)** - Development/testing
2. **Blaze Plan (Pay-as-you-go)** - Production ready
3. **Enterprise** - Large organizations

### For Smart Eat: Use **Blaze Plan**

**Why Blaze Plan for Restaurant Management:**
- ✅ **Scalable** - Grows with your restaurant
- ✅ **Pay-per-use** - Only pay for what you use
- ✅ **No upfront costs** - Perfect for small/medium businesses
- ✅ **Production features** - Full feature set
- ✅ **Free tier included** - Generous free limits

**Free Tier Limits (usually sufficient for small restaurants):**
- 1GB Firestore storage
- 50,000 reads/day
- 20,000 writes/day
- 20,000 deletes/day
- 1GB hosting bandwidth

**Pricing Example for Small Restaurant:**
- 100 daily active users
- 500 orders/month
- ~$1-5/month (very affordable)

**Enterprise Plan** - Only if you have:
- Multiple restaurant locations
- Thousands of daily users
- Custom SLA requirements
- Advanced security needs

**Recommendation: Start with Blaze Plan** 🚀

---

## 🔐 Step 2: Enable Authentication

### 2.1 Access Authentication
1. In Firebase Console, click **"Authentication"** in the left sidebar
2. Click **"Get started"**

### 2.2 Enable Email/Password Sign-in
1. Click **"Sign-in method"** tab
2. Find **"Email/Password"** in the provider list
3. Click on it
4. Toggle **"Enable"** switch → **ON**
5. Click **"Save"**

### 2.3 Verify Setup
- You should see Email/Password as **"Enabled"**
- Status should be green

---

## 📊 Step 3: Set Up Firestore Database

### 3.1 Access Firestore
1. In Firebase Console, click **"Firestore Database"** in the left sidebar
2. Click **"Create database"**

### 3.2 Choose Database Mode
1. Select **"Start in test mode"** (we'll configure security rules later)
2. Click **"Next"**

### 3.2.1 Database ID (Optional)
- **Default**: Leave as `(default)` 
- **Custom**: You can specify a custom database ID if you need multiple databases
- **For Smart Eat**: Use the default `(default)` database ID
- This ID is used in your code when referencing the database

**Note**: Your Flutter code already uses the default database, so no changes needed in `firebase_service.dart`.

### 3.3 Configure Location
1. Choose a location close to your users (e.g., `asia-southeast1` for Southeast Asia)
2. Click **"Done"**

### 3.4 Wait for Setup
- Firestore will initialize (takes 1-2 minutes)
- You'll see the database dashboard

---

## 🔑 Step 4: Get Firebase Configuration

### 4.1 Access Project Settings
1. Click the **⚙️ gear icon** → **"Project settings"**
2. Scroll down to **"Your apps"** section

### 4.2 Add Web App
1. Click **"Add app"** → **"</>" icon** (Web app)
2. Enter app details:
   - **App nickname**: `Smart Eat Web`
   - **Also set up Firebase Hosting**: Leave unchecked for now
3. Click **"Register app"**

### 4.3 Copy Configuration
1. You'll see Firebase config code
2. **Copy the entire config object** - it looks like this:
```javascript
const firebaseConfig = {
  apiKey: "AIzaSyC...your-api-key...",
  authDomain: "smart-eat-123.firebaseapp.com",
  projectId: "smart-eat-123",
  storageBucket: "smart-eat-123.appspot.com",
  messagingSenderId: "123456789012",
  appId: "1:123456789012:web:abcdef123456",
  measurementId: "G-XXXXXXXXXX"
};
```
3. **Save this config** - you'll need it for Flutter

### 4.4 Skip Hosting Setup
1. Click **"Continue to console"** (skip Firebase Hosting for now)

---

## 🛡️ Step 5: Configure Security Rules

### 5.1 Access Firestore Rules
1. In Firebase Console, go to **"Firestore Database"**
2. Click **"Rules"** tab

### 5.2 Update Security Rules
1. Replace the existing rules with this production-ready code:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only access their own profile
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // Allow authenticated users to read/write data for their restaurant
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

### 5.3 Publish Rules
1. Click **"Publish"**
2. Confirm the changes

---

## 📱 Step 6: Configure Flutter App

### 6.1 Update Firebase Configuration
1. Open `lib/services/firebase_service.dart`
2. Find the `FirebaseOptions` configuration
3. Replace the placeholder values with your Firebase config:

```dart
options: const FirebaseOptions(
  apiKey: "YOUR_API_KEY_HERE",
  authDomain: "YOUR_PROJECT_ID.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT_ID.appspot.com",
  messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
  appId: "YOUR_APP_ID",
  measurementId: "YOUR_MEASUREMENT_ID", // Optional
),
```

**Example:**
```dart
options: const FirebaseOptions(
  apiKey: "AIzaSyC8rF8xYzDw9qLpN7mK9pQrT5vHnS8wXyZ",
  authDomain: "smart-eat-demo.firebaseapp.com",
  projectId: "smart-eat-demo",
  storageBucket: "smart-eat-demo.appspot.com",
  messagingSenderId: "123456789012",
  appId: "1:123456789012:web:abcdef1234567890",
  measurementId: "G-ABCDEFGHIJ",
),
```

### 6.2 Run the App
```bash
cd /path/to/your/smart-eat/frontend
flutter run -d chrome
```

---

## 🧪 Step 7: Test the Setup

### 7.1 Test Authentication
1. Open the app in browser
2. Try to **register a new account**:
   - Enter email and password
   - Click "Sign In" (it will create account if it doesn't exist)
3. Check Firebase Console → **Authentication** → **Users**
4. Verify your user appears in the list

### 7.2 Test Firestore
1. In app, try to **add a menu item**
2. Check Firebase Console → **Firestore Database**
3. Verify data appears in collections:
   - `menu` collection should have your menu item
   - `users` collection should have your user profile

### 7.3 Test Data Operations
1. **Create menu items** in the app
2. **Create orders** in POS screen
3. **Check inventory** operations
4. Verify all data syncs to Firestore

---

## 🔧 Step 8: Advanced Configuration (Optional)

### 8.1 Enable Additional Auth Providers
1. Go to **Authentication** → **Sign-in method**
2. Enable **Google**, **Phone**, etc. if needed

### 8.2 Set Up Firebase Hosting (Optional)
1. Install Firebase CLI: `npm install -g firebase-tools`
2. Login: `firebase login`
3. Initialize hosting: `firebase init`
4. Deploy: `firebase deploy`

### 8.3 Configure Analytics (Optional)
1. Go to **Analytics** in Firebase Console
2. Set up custom events for restaurant metrics
3. Configure conversion tracking

---

## 🐛 Troubleshooting

### Issue: "Firebase app not initialized"
**Solution:** Double-check your Firebase config in `firebase_service.dart`

### Issue: "Permission denied"
**Solution:** Check Firestore security rules - ensure they're published

### Issue: "Auth/network-request-failed"
**Solution:** Check your internet connection and Firebase project status

### Issue: "Invalid API key"
**Solution:** Verify your API key in the Firebase config

### Issue: App won't start
**Solution:**
```bash
flutter clean
flutter pub get
flutter run -d chrome
```

---

## 📊 Firebase Console Monitoring

### Check Your Data:
1. **Authentication**: View registered users
2. **Firestore**: Browse collections and documents
3. **Analytics**: Monitor app usage and performance
4. **Functions**: Check server-side functions (if any)
5. **Storage**: Manage file uploads (if implemented)

### Monitor Performance:
1. Go to **Performance** tab
2. View app startup times, network requests
3. Monitor Firestore query performance

---

## 🎯 Next Steps After Setup

1. **Test all features** thoroughly
2. **Set up production security rules** (more restrictive)
3. **Configure backup** policies in Firestore
4. **Set up monitoring** and alerts
5. **Consider Firebase Hosting** for production deployment

---

## 📞 Support

If you encounter issues:
1. Check the [Firebase Documentation](https://firebase.google.com/docs)
2. Visit [Firebase Community](https://firebase.google.com/community)
3. Check FlutterFire docs: https://firebase.google.com/docs/flutter/setup

**Your Smart Eat app is now fully connected to Firebase!** 🎉
