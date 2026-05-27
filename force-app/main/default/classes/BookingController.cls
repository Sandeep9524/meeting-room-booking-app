public with sharing class BookingController {

    /**
     * Accepts either:
     *   "YYYY-MM-DD HH:mm:ss"  — plain local string, parsed as ORG timezone by DateTime.valueOf()
     *   ISO-8601 with Z/offset — parsed as UTC/offset-aware
     */
    // Use org timezone offset — org is now set to IST (UTC+5:30)

    private static DateTime parseDateTime(String s) {
        if (String.isBlank(s)) {
            throw new AuraHandledException('Empty datetime string');
        }
        try {
            if (!s.contains('Z') && !s.contains('+') &&
                !(s.contains('T') && s.length() > 19)) {
                // Parse "YYYY-MM-DD HH:mm:ss" as IST local time → convert to UTC
                String datePart = s.split(' ')[0];
                String timePart = s.split(' ')[1];
                List<String> dp = datePart.split('-');
                List<String> tp = timePart.split(':');
                Integer yr  = Integer.valueOf(dp[0]);
                Integer mo  = Integer.valueOf(dp[1]);
                Integer dy  = Integer.valueOf(dp[2]);
                Integer hr  = Integer.valueOf(tp[0]);
                Integer mn  = Integer.valueOf(tp[1]);
                Integer sec = tp.size() > 2 ? Integer.valueOf(tp[2]) : 0;
                // Method 2 from verify script — the only method that gives correct UTC
                DateTime asGmt   = DateTime.newInstanceGmt(yr, mo, dy, hr, mn, sec);
                Integer  offsetMs = UserInfo.getTimeZone().getOffset(asGmt);
                return asGmt.addSeconds(-(offsetMs / 1000));
            }
            return (DateTime) JSON.deserialize('"' + s + '"', DateTime.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid datetime: ' + s + ' (' + e.getMessage() + ')');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<RoomOption> getRooms() {
        List<RoomOption> out = new List<RoomOption>();
        for (Meeting_Room__c r : [SELECT Id, Name FROM Meeting_Room__c ORDER BY Name ASC]) {
            out.add(new RoomOption(r.Id, r.Name));
        }
        return out;
    }

    @AuraEnabled
    public static List<BookingWrapper> getBookings() {
        List<Booking__c> rows = [
            SELECT Id, Name, Room_Name__c, Room_Name__r.Name,
                   Employee_Name__c, Start_Time__c, End_Time__c, Status__c
            FROM Booking__c
            WHERE Status__c = 'Booked'
            ORDER BY Start_Time__c ASC
            LIMIT 200
        ];
        List<BookingWrapper> out = new List<BookingWrapper>();
        for (Booking__c b : rows) out.add(new BookingWrapper(b));
        return out;
    }

    @AuraEnabled
    public static Boolean checkAvailability(String roomId, String startTime, String endTime) {
        try {
            DateTime startDT = parseDateTime(startTime);
            DateTime endDT   = parseDateTime(endTime);
            DateTime nowDT   = DateTime.now(); // must be a variable — :DateTime.now() is invalid SOQL
            List<Booking__c> conflicts = [
                SELECT Id FROM Booking__c
                WHERE Room_Name__c = :roomId
                  AND Status__c    = 'Booked'
                  AND Start_Time__c < :endDT
                  AND End_Time__c   > :startDT
                  AND End_Time__c   > :nowDT
                LIMIT 1
            ];
            return conflicts.isEmpty();
        } catch (Exception e) {
            throw new AuraHandledException('Error checking availability: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Booking__c createBooking(
            String roomId, String employeeName, String startTime, String endTime) {
        try {
            DateTime startDT = parseDateTime(startTime);
            DateTime endDT   = parseDateTime(endTime);

            // Reject past bookings
            if (startDT < DateTime.now()) {
                throw new AuraHandledException('Cannot book a slot in the past.');
            }

            // Double-check for conflicts before insert — ignore elapsed bookings
            DateTime nowDT = DateTime.now();
            List<Booking__c> conflicts = [
                SELECT Id FROM Booking__c
                WHERE Room_Name__c = :roomId
                  AND Status__c    = 'Booked'
                  AND Start_Time__c < :endDT
                  AND End_Time__c   > :startDT
                  AND End_Time__c   > :nowDT
                LIMIT 1
            ];
            if (!conflicts.isEmpty()) {
                // Fetch full details of the conflicting booking for a helpful error message
                Booking__c clash = [
                    SELECT Name, Employee_Name__c, Start_Time__c, End_Time__c
                    FROM Booking__c WHERE Id = :conflicts[0].Id LIMIT 1
                ];
                String tzId       = UserInfo.getTimeZone().getID();
                String clashStart = clash.Start_Time__c.format('dd-MM-yyyy hh:mm a', tzId);
                String clashEnd   = clash.End_Time__c.format('hh:mm a', tzId);
                throw new AuraHandledException(
                    'Conflict with ' + clash.Name + ' (' + clash.Employee_Name__c + ') — ' +
                    clashStart + ' to ' + clashEnd + '. Please choose a different slot.'
                );
            }

            Booking__c rec = new Booking__c(
                Room_Name__c     = roomId,
                Employee_Name__c = employeeName,
                Start_Time__c    = startDT,
                End_Time__c      = endDT,
                Status__c        = 'Booked'
            );
            insert rec;
            return rec;

        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw new AuraHandledException('Database error: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Unexpected error: ' + e.getMessage());
        }
    }

    // ── Wrapper classes ───────────────────────────────────────────────────────

    @AuraEnabled
    public static void cancelBooking(String bookingId) {
        try {
            Booking__c b = [SELECT Id, Name, Status__c, Start_Time__c FROM Booking__c WHERE Id = :bookingId LIMIT 1];
            if (b.Status__c == 'Canceled') {
                throw new AuraHandledException('This booking is already canceled.');
            }
            // Delete the record so the slot is immediately free — no conflict query issues
            delete b;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to cancel booking: ' + e.getMessage());
        }
    }

    public class BookingWrapper {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String RoomId;
        @AuraEnabled public String RoomName;
        @AuraEnabled public String EmployeeName;
        @AuraEnabled public String Status;
        @AuraEnabled public String DisplayStart;
        @AuraEnabled public String DisplayEnd;
        @AuraEnabled public Long   StartTimeMs; // kept for reference but not used for date matching
        @AuraEnabled public Long   EndTimeMs;
        // Local datetime strings in YYYY-MM-DD HH:mm format — used by JS for calendar matching
        @AuraEnabled public String StartLocal;
        @AuraEnabled public String EndLocal;

        public BookingWrapper(Booking__c b) {
            this.Id           = b.Id;
            this.Name         = b.Name;
            this.RoomId       = b.Room_Name__c;
            this.RoomName     = b.Room_Name__r != null ? b.Room_Name__r.Name : '';
            this.EmployeeName = b.Employee_Name__c;
            this.Status       = b.Status__c;
            this.StartTimeMs  = b.Start_Time__c.getTime();
            this.EndTimeMs    = b.End_Time__c.getTime();
            String tzId       = UserInfo.getTimeZone().getID(); // org TZ is now IST
            this.StartLocal   = b.Start_Time__c.format('yyyy-MM-dd HH:mm', tzId);
            this.EndLocal     = b.End_Time__c.format(  'yyyy-MM-dd HH:mm', tzId);
            this.DisplayStart = b.Start_Time__c.format('dd-MM-yyyy hh:mm a', tzId);
            this.DisplayEnd   = b.End_Time__c.format(  'dd-MM-yyyy hh:mm a', tzId);
        }
    }

    public class RoomOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public RoomOption(String v, String l) { this.value = v; this.label = l; }
    }
}