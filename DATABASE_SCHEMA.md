# Smart Eat - Database Schema (Firebase Firestore)

## Collections Overview

### 1. Users Collection
```javascript
{
  id: string,           // Document ID
  email: string,        // User email (unique)
  password: string,     // Hashed password
  name: string,         // Full name
  role: string,         // 'admin', 'manager', 'staff', 'cashier', 'kitchen'
  eateryId: string,     // Associated eatery/restaurant
  isActive: boolean,    // Account status
  createdAt: timestamp,  // Account creation
  updatedAt: timestamp   // Last update
}
```

### 2. Menu Items Collection
```javascript
{
  id: string,           // Document ID
  name: string,         // Item name
  category: string,      // Food category
  price: number,        // Selling price
  cost: number,         // Cost price
  description: string,   // Item description
  ingredients: array,    // Required ingredients
  isAvailable: boolean, // Availability status
  image: string,        // Image URL
  eateryId: string,     // Associated eatery
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### 3. Orders Collection
```javascript
{
  id: string,           // Document ID
  orderNumber: string,   // Order number (e.g., ORD-001)
  items: array,         // Order items
  [
    {
      menuItemId: string,
      name: string,
      quantity: number,
      price: number,
      subtotal: number
    }
  ],
  totalAmount: number,   // Total order value
  paymentMethod: string, // 'cash', 'card', 'digital'
  status: string,       // 'pending', 'preparing', 'ready', 'completed'
  notes: string,        // Order notes
  eateryId: string,     // Associated eatery
  staffId: string,      // Staff who processed order
  createdAt: timestamp,
  completedAt: timestamp
}
```

### 4. Inventory Collection
```javascript
{
  id: string,           // Document ID
  name: string,         // Ingredient name
  category: string,      // Ingredient category
  currentStock: number,  // Current quantity
  unit: string,         // Measurement unit (kg, liters, pieces)
  minStock: number,     // Minimum stock level
  unitCost: number,     // Cost per unit
  supplier: string,      // Supplier name
  lastRestocked: timestamp,
  eateryId: string,     // Associated eatery
  createdAt: timestamp,
  updatedAt: timestamp
}
```

### 5. Inventory Usage Collection
```javascript
{
  id: string,           // Document ID
  ingredientId: string,  // Reference to inventory item
  orderId: string,       // Reference to order
  quantityUsed: number,  // Amount used
  unitCost: number,     // Cost at time of usage
  eateryId: string,     // Associated eatery
  createdAt: timestamp
}
```

### 6. Analytics Collection
```javascript
{
  id: string,           // Document ID
  type: string,         // 'daily_sales', 'weekly_sales', 'monthly_sales'
  period: string,       // Date period (YYYY-MM-DD, YYYY-WXX, YYYY-MM)
  data: object,         // Analytics data
  {
    totalRevenue: number,
    totalOrders: number,
    averageOrderValue: number,
    topItems: array,
    peakHours: array,
    categoryBreakdown: object
  },
  eateryId: string,     // Associated eatery
  generatedAt: timestamp
}
```

### 7. Settings Collection
```javascript
{
  id: string,           // Document ID (usually eateryId)
  eateryName: string,   // Restaurant name
  currency: string,     // Currency code (PHP, USD, etc.)
  timezone: string,     // Business timezone
  businessHours: object, // Operating hours
  taxRate: number,      // Tax percentage
  lowStockThreshold: number, // Alert threshold
  eateryId: string,     // Document ID = eateryId
  updatedAt: timestamp
}
```

## Indexes for Performance

### Users Collection
- `email` (ascending) - For login queries
- `eateryId` (ascending) - For staff listing

### Orders Collection
- `eateryId` + `createdAt` (composite) - For order history
- `eateryId` + `status` (composite) - For order tracking
- `orderNumber` (ascending) - For order lookup

### Menu Items Collection
- `eateryId` + `category` (composite) - For menu categorization
- `eateryId` + `isAvailable` (composite) - For available items

### Inventory Collection
- `eateryId` + `category` (composite) - For inventory management
- `eateryId` + `currentStock` (composite) - For stock alerts

### Analytics Collection
- `eateryId` + `type` + `period` (composite) - For analytics queries

## Data Flow

1. **Order Process**: Order → Inventory Usage → Sales Analytics
2. **Inventory Management**: Stock Updates → Low Stock Alerts → Reorder Suggestions
3. **ML Processing**: Historical Orders → Demand Forecast → Recommendations
4. **User Management**: Role-based Access → Feature Permissions → Audit Trail

## Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only access their eatery's data
    match /{document=**} {
      allow read, write: if request.auth != null && 
        request.auth.token.eateryId == resource.data.eateryId;
    }
    
    // Admins have broader access
    match /users/{userId} {
      allow read, write: if request.auth != null && 
        (request.auth.token.eateryId == resource.data.eateryId ||
         request.auth.token.role == 'admin');
    }
  }
}
```
