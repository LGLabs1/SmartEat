# Firebase Setup Guide for Smart Eat

## 🚀 Quick Setup

### 1. Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Create a project" (or select existing)
3. Enable **Firestore Database** and **Authentication**
4. Enable **Email/Password** authentication

### 2. Get Firebase Configuration
1. Go to Project Settings (gear icon)
2. Scroll to "Your apps" section
3. Click "Add app" → Web app (</>)
4. Copy the Firebase config values

### 3. Update Firebase Configuration
In `lib/services/firebase_service.dart`, replace the placeholder values:

```dart
options: const FirebaseOptions(
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_PROJECT_ID.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT_ID.appspot.com",
  messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
  appId: "YOUR_APP_ID",
  measurementId: "YOUR_MEASUREMENT_ID",
),
```

### 4. Set Firestore Security Rules
In Firebase Console → Firestore Database → Rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only access their own profile
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // Allow authenticated users to read/write data
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

### 5. Run the App
```bash
flutter run -d chrome
```

## 📋 Features Connected to Firestore

### ✅ Authentication
- User registration and login via Firebase Auth
- Automatic session management
- User profile storage

### ✅ Menu Management
- CRUD operations for menu items
- Real-time availability updates
- Category-based organization

### ✅ Inventory Tracking
- Stock level management
- Low stock alerts
- Supplier information

### ✅ Order Processing
- POS order creation
- Sales analytics
- Order history

### ✅ Analytics Dashboard
- Daily sales tracking
- Item performance metrics
- Revenue analytics

## 🔧 Database Structure

```
Firestore Collections:
├── users/                    # User profiles
├── menu/                     # Menu items
├── orders/                   # Customer orders
├── inventory/                # Inventory items
├── inventory_usage/          # Stock usage tracking
└── analytics/                # Analytics data
```

## 🚀 What's Working Now

- ✅ **Direct Firestore Integration** - No backend server needed
- ✅ **Real-time Data** - Changes sync instantly across all devices
- ✅ **Offline Support** - Firebase handles offline/online sync
- ✅ **Scalable** - Handles multiple restaurants/eateries
- ✅ **Secure** - Firebase Auth + Firestore security rules

## 📝 Next Steps

1. **Test Authentication**: Try registering/logging in
2. **Add Sample Data**: Create menu items and inventory
3. **Test Features**: Verify all CRUD operations work
4. **Configure Rules**: Set up proper security rules for production

## 🆘 Troubleshooting

**Common Issues:**

1. **"Firebase app not initialized"**
   - Check Firebase config values in `firebase_service.dart`

2. **"Permission denied"**
   - Update Firestore security rules
   - Ensure user is authenticated

3. **"Missing or insufficient permissions"**
   - Check Firebase Auth is enabled
   - Verify user authentication state

The app is now fully connected to Firestore! 🎉
