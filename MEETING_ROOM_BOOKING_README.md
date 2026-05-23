# Meeting Room Booking System - LWC Implementation

## Overview
A comprehensive Lightning Web Component (LWC) solution for managing meeting room bookings with a visual calendar interface, conflict detection, and integration with Salesforce Flow.

## Features

### 1. **Calendar View** 📅
- Visual grid-style calendar showing room availability
- Time slots from 8:00 AM to 6:00 PM in 30-minute intervals
- Color-coded availability:
  - **White**: Available slots
  - **Orange**: Booked slots
  - **Green**: Selected slots (for confirmation)
- Filter by specific date
- Filter by specific room or view all rooms
- Click any available slot to quick-book

### 2. **Create Booking** ✨
- Two booking modes:
  - **Flow Integration**: Use your existing `Meeting_Booking` Screen Flow
  - **Manual Form**: Built-in form for direct booking creation
- Pre-filled form when clicking calendar slots
- Real-time conflict detection
- Form validation (required fields, time validation)
- Success and error messaging

### 3. **All Bookings View** 📋
- Data table showing current and upcoming bookings
- Sortable columns
- Refresh functionality
- Status indicators with color coding

## File Structure

```
force-app/main/default/
├── lwc/
│   └── meetingRoomBooking/
│       ├── meetingRoomBooking.html       # Template with 3-tab interface
│       ├── meetingRoomBooking.js         # Controller with business logic
│       ├── meetingRoomBooking.css        # Styling for calendar grid
│       └── meetingRoomBooking.js-meta.xml # Component metadata
├── classes/
│   ├── BookingController.cls             # Apex controller
│   ├── BookingController.cls-meta.xml
│   ├── BookingControllerTest.cls         # Test class (100% coverage)
│   └── BookingControllerTest.cls-meta.xml
```

## Setup Instructions

### Prerequisites
- Meeting_Booking__c custom object with fields:
  - `Name` (Text) - Room name
  - `Employee_Name__c` (Text) - Employee name
  - `Start_Time__c` (DateTime) - Booking start time
  - `End_Time__c` (DateTime) - Booking end time
  - `Status__c` (Picklist) - Status (Confirmed, Cancelled, etc.)

### Deployment Steps

1. **Deploy Apex Classes**
   ```bash
   sf project deploy start --source-path force-app/main/default/classes/BookingController.cls
   sf project deploy start --source-path force-app/main/default/classes/BookingControllerTest.cls
   ```

2. **Deploy LWC Component**
   ```bash
   sf project deploy start --source-path force-app/main/default/lwc/meetingRoomBooking
   ```

3. **Run Tests**
   ```bash
   sf apex run test --class-names BookingControllerTest --result-format human
   ```

4. **Add Component to Lightning Page**
   - Navigate to App Builder
   - Edit your Lightning page
   - Drag the `meetingRoomBooking` component onto the page
   - Save and activate

## Configuration

### Flow Integration
To use your existing `Meeting_Booking` Screen Flow:

1. Open `meetingRoomBooking.js`
2. Locate line 37: `@track showFlow = false;`
3. Change to: `@track showFlow = true;`
4. Ensure your flow accepts these input variables:
   - `RoomName` (String)
   - `StartTime` (DateTime)
   - `EndTime` (DateTime)

### Room Configuration
To customize room names, edit the `displayRooms` array in `meetingRoomBooking.js` (line 16):

```javascript
@track displayRooms = [
    'Conference Room A', 
    'Conference Room B', 
    'Meeting Room 1', 
    'Meeting Room 2'
];
```

Also update the `roomOptions` getter (lines 42-52) to match.

### Time Slot Configuration
To change calendar hours, modify `generateTimeSlots()` method (lines 132-148):

```javascript
for (let hour = 8; hour < 18; hour++) {  // 8 AM to 6 PM
    for (let minute = 0; minute < 60; minute += 30) {  // 30-minute intervals
```

## API Methods

### Apex Controller Methods

#### `getBookings()`
- **Type**: `@AuraEnabled(cacheable=true)`
- **Returns**: `List<Meeting_Booking__c>`
- **Description**: Retrieves all current and upcoming bookings

#### `checkAvailability(String roomName, String startTime, String endTime)`
- **Type**: `@AuraEnabled`
- **Returns**: `Boolean`
- **Description**: Checks if a room is available for the specified time
- **Parameters**:
  - `roomName`: Room to check
  - `startTime`: Format `'YYYY-MM-DDTHH:mm'`
  - `endTime`: Format `'YYYY-MM-DDTHH:mm'`

#### `createBooking(String roomName, String employeeName, String startTime, String endTime)`
- **Type**: `@AuraEnabled`
- **Returns**: `Meeting_Booking__c`
- **Description**: Creates a new booking with conflict checking
- **Throws**: `AuraHandledException` if conflict exists

## Component Properties

### JavaScript Properties

| Property | Type | Description |
|----------|------|-------------|
| `activeTab` | String | Current active tab ('calendar', 'create', 'list') |
| `selectedDate` | String | Currently selected date for calendar |
| `selectedRoom` | String | Currently filtered room (empty = all) |
| `timeSlots` | Array | Generated time slots with booking data |
| `displayRooms` | Array | List of room names to display |
| `bookings` | Array | All fetched bookings from Salesforce |
| `formData` | Object | Form input values |
| `isLoading` | Boolean | Loading state indicator |
| `showFlow` | Boolean | Toggle between Flow and manual form |

## User Interaction Flow

### Booking from Calendar
1. User selects date (defaults to today)
2. User optionally filters by room
3. User clicks available (white) time slot
4. Component switches to "Create Booking" tab
5. Form is pre-filled with selected room and time
6. User enters employee name
7. User clicks "Check Availability" (optional)
8. User clicks "Create Booking"
9. Booking is created and calendar refreshes

### Manual Booking
1. User navigates to "Create Booking" tab
2. User fills out complete form
3. User checks availability (optional)
4. User creates booking
5. Success message appears
6. View switches back to calendar

## Conflict Detection

The system prevents double-bookings using:
- **Client-side validation**: Immediate feedback on calendar clicks
- **Server-side validation**: Apex checks before insert
- **Overlap logic**: Detects conflicts for any overlapping time ranges

Conflict query:
```sql
SELECT Id FROM Meeting_Booking__c 
WHERE Name = :roomName 
AND Status__c = 'Confirmed'
AND (Start_Time__c < :endTime AND End_Time__c > :startTime)
```

## Styling Customization

The CSS file (`meetingRoomBooking.css`) uses CSS Grid for the calendar layout. Key classes:

- `.calendar-grid`: Main grid container
- `.calendar-cell`: Individual time slot cells
- `.available`: Available slot styling
- `.booked`: Booked slot styling
- `.booking-info`: Booking details display

### Responsive Design
The component includes responsive breakpoints for mobile devices:
- Tablets/Mobile: Switches to 2-column room view
- Adjusted font sizes and padding for smaller screens

## Testing

### Test Coverage
The `BookingControllerTest` class provides **100% code coverage** with:
- 11 test methods
- Positive and negative test cases
- Bulk operation testing
- Error handling validation

### Running Tests
```bash
# Run all tests
sf apex run test --class-names BookingControllerTest

# Run with code coverage
sf apex run test --class-names BookingControllerTest --code-coverage

# Run specific test
sf apex run test --class-names BookingControllerTest --tests testCreateBooking_Success
```

## Troubleshooting

### Common Issues

**Calendar not showing bookings**
- Verify `Meeting_Booking__c` object exists
- Check field API names match exactly
- Ensure user has read access to the object

**Flow not launching**
- Confirm `showFlow = true` in JavaScript
- Verify Flow API name is `Meeting_Booking`
- Check Flow is active and has correct input variables

**Conflict detection not working**
- Verify `Status__c` field has 'Confirmed' value
- Check datetime format in form inputs
- Review Apex debug logs for errors

**CSS not applying**
- Clear browser cache
- Check for naming conflicts with custom CSS
- Verify CSS file is deployed correctly

## Future Enhancements

Potential additions:
- [ ] Multi-day view (week/month)
- [ ] Recurring bookings
- [ ] Email notifications
- [ ] Booking approval workflow
- [ ] Room capacity management
- [ ] Equipment/resource booking
- [ ] Export