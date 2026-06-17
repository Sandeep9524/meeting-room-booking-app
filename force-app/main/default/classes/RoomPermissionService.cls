public with sharing class RoomPermissionService {

    // ── Check if current user can book a specific room ────────────────────────
    @AuraEnabled(cacheable=true)
    public static PermissionResult checkRoomPermission(String roomId) {
        try {
            // Get room name
            Meeting_Room__c room = [
                SELECT Id, Name FROM Meeting_Room__c WHERE Id = :roomId LIMIT 1
            ];

            // Get permission config for this room
            List<Room_Permission__mdt> configs = [
                SELECT Room_Name__c, Required_Permission__c,
                       Requires_Approval__c, Restriction_Message__c
                FROM Room_Permission__mdt
                WHERE Room_Name__c = :room.Name
                LIMIT 1
            ];

            // No config = open to all
            if (configs.isEmpty()) {
                return new PermissionResult(true, false, '');
            }

            Room_Permission__mdt config = configs[0];

            // No permission required = open to all
            if (String.isBlank(config.Required_Permission__c)) {
                return new PermissionResult(true, config.Requires_Approval__c, '');
            }

            // Check if user has the required permission set
            Boolean hasPermission = userHasPermissionSet(config.Required_Permission__c);

            if (!hasPermission) {
                String msg = String.isNotBlank(config.Restriction_Message__c)
                    ? config.Restriction_Message__c
                    : 'You do not have permission to book ' + room.Name;
                return new PermissionResult(false, false, msg);
            }

            return new PermissionResult(true, config.Requires_Approval__c, '');

        } catch (Exception e) {
            // Default allow if config fails — never block booking due to config error
            return new PermissionResult(true, false, '');
        }
    }

    // ── Get permissions for all rooms at once (for calendar UI) ──────────────
    @AuraEnabled(cacheable=true)
    public static List<RoomPermissionInfo> getAllRoomPermissions() {
        List<RoomPermissionInfo> result = new List<RoomPermissionInfo>();

        List<Meeting_Room__c> rooms = [SELECT Id, Name FROM Meeting_Room__c ORDER BY Name ASC];
        List<Room_Permission__mdt> configs = [
            SELECT Room_Name__c, Required_Permission__c,
                   Requires_Approval__c, Restriction_Message__c
            FROM Room_Permission__mdt
        ];

        // Build map for quick lookup
        Map<String, Room_Permission__mdt> configMap = new Map<String, Room_Permission__mdt>();
        for (Room_Permission__mdt c : configs) {
            configMap.put(c.Room_Name__c, c);
        }

        for (Meeting_Room__c room : rooms) {
            Room_Permission__mdt config = configMap.get(room.Name);
            Boolean canBook = true;
            Boolean needsApproval = false;
            String message = '';

            if (config != null && String.isNotBlank(config.Required_Permission__c)) {
                canBook = userHasPermissionSet(config.Required_Permission__c);
                needsApproval = config.Requires_Approval__c;
                if (!canBook) {
                    message = String.isNotBlank(config.Restriction_Message__c)
                        ? config.Restriction_Message__c
                        : 'Restricted: ' + room.Name;
                }
            }

            result.add(new RoomPermissionInfo(room.Id, room.Name, canBook, needsApproval, message));
        }

        return result;
    }

    // ── Check if current user has a specific permission set ───────────────────
    private static Map<String, Boolean> permissionCache = new Map<String, Boolean>();

    private static Boolean userHasPermissionSet(String permSetName) {
        if (permissionCache.containsKey(permSetName)) {
            return permissionCache.get(permSetName);
        }

        // Booking_Admin can book everything
        List<PermissionSetAssignment> adminCheck = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.Name = 'BookingAdmin'
            LIMIT 1
        ];
        if (!adminCheck.isEmpty()) {
            permissionCache.put(permSetName, true);
            return true;
        }

        List<PermissionSetAssignment> assignments = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.Name = :permSetName
            LIMIT 1
        ];

        Boolean result = !assignments.isEmpty();
        permissionCache.put(permSetName, result);
        return result;
    }

    // ── Validate permission in createBooking (server-side enforcement) ────────
    public static void enforceRoomPermission(String roomId) {
        PermissionResult result = checkRoomPermission(roomId);
        if (!result.canBook) {
            throw new AuraHandledException(result.message);
        }
    }

    // ── Wrapper classes ───────────────────────────────────────────────────────
    public class PermissionResult {
        @AuraEnabled public Boolean canBook;
        @AuraEnabled public Boolean requiresApproval;
        @AuraEnabled public String  message;

        public PermissionResult(Boolean canBook, Boolean requiresApproval, String message) {
            this.canBook          = canBook;
            this.requiresApproval = requiresApproval;
            this.message          = message;
        }
    }

    public class RoomPermissionInfo {
        @AuraEnabled public String  roomId;
        @AuraEnabled public String  roomName;
        @AuraEnabled public Boolean canBook;
        @AuraEnabled public Boolean requiresApproval;
        @AuraEnabled public String  message;

        public RoomPermissionInfo(String roomId, String roomName,
                Boolean canBook, Boolean requiresApproval, String message) {
            this.roomId           = roomId;
            this.roomName         = roomName;
            this.canBook          = canBook;
            this.requiresApproval = requiresApproval;
            this.message          = message;
        }
    }
}