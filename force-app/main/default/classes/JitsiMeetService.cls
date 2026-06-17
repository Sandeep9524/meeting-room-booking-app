public with sharing class JitsiMeetService {

    /**
     * Generates a unique Jitsi Meet link for a booking.
     * Format: https://meet.jit.si/BookingBR-0107-SandeepNayak
     *
     * No API key, no OAuth, no external setup required.
     * Anyone with the link can join — share it with attendees.
     */
    public static String generateLink(Id bookingId, String employeeName) {
        // Build a unique, URL-safe room name
        // Use booking record name + cleaned employee name for readability
        String bookingName = '';
        try {
            Booking__c b = [SELECT Name FROM Booking__c WHERE Id = :bookingId LIMIT 1];
            bookingName = b.Name;
        } catch (Exception e) {
            bookingName = String.valueOf(bookingId).substring(0, 8);
        }

        // Clean employee name — remove spaces and special chars
        String cleanEmployee = '';
        if (String.isNotBlank(employeeName)) {
            cleanEmployee = '-' + employeeName.replaceAll('[^a-zA-Z0-9]', '');
        }

        // Add a short random suffix for extra uniqueness
        String suffix = EncodingUtil.convertToHex(
            Crypto.generateDigest('MD5', Blob.valueOf(bookingId + String.valueOf(DateTime.now().getTime())))
        ).substring(0, 6);

        String roomName = 'Booking' + bookingName + cleanEmployee + '-' + suffix;

        return 'https://meet.jit.si/' + roomName;
    }
}