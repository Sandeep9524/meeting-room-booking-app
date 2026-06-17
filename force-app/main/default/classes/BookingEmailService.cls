public with sharing class BookingEmailService {

    public static void sendBookingConfirmation(Booking__c booking, String attendeeEmail) {
        try {
            String roomName     = booking.Room_Name__r != null ? booking.Room_Name__r.Name : 'Meeting Room';
            String employeeName = booking.Employee_Name__c;
            String meetLink     = booking.Meeting_Link__c;
            TimeZone tz         = UserInfo.getTimeZone();
            String startStr     = booking.Start_Time__c.format('dd-MM-yyyy hh:mm a', tz.getID());
            String endStr       = booking.End_Time__c.format('hh:mm a', tz.getID());

            // Send to booker always; also to attendee if email provided
            List<String> toAddresses = new List<String>{ UserInfo.getUserEmail() };
            if (String.isNotBlank(attendeeEmail) && attendeeEmail.contains('@')) {
                toAddresses.add(attendeeEmail);
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(toAddresses);
            mail.setSenderDisplayName('Meeting Room Booking System');
            mail.setSubject('Meeting Booked: ' + roomName + ' — ' + startStr);

            // Use first available org-wide email address (avoids domain verification error)
            List<OrgWideEmailAddress> owas = [
                SELECT Id, Address FROM OrgWideEmailAddress LIMIT 1
            ];
            if (!owas.isEmpty()) {
                mail.setOrgWideEmailAddressId(owas[0].Id);
            }
            mail.setHtmlBody(buildEmailBody(
                booking.Name, roomName, employeeName, startStr, endStr, meetLink
            ));
            mail.setSaveAsActivity(false);

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            System.debug('Booking confirmation email sent to: ' + toAddresses);

        } catch (Exception e) {
            System.debug('Email send failed: ' + e.getMessage());
        }
    }

    private static String buildEmailBody(
        String bookingName, String roomName, String employeeName,
        String startStr, String endStr, String meetLink
    ) {
        String joinButton = String.isNotBlank(meetLink)
            ? '<a href="' + meetLink + '" style="display:inline-block;padding:12px 28px;' +
              'background:#0176d3;color:#fff;text-decoration:none;border-radius:4px;' +
              'font-weight:600;font-size:15px;margin-top:16px;">&#127909; Join Meeting</a>'
            : '<p style="color:#888">Meeting link not available</p>';

        return '<!DOCTYPE html><html><body style="font-family:Arial,sans-serif;background:#f4f6f9;margin:0;padding:0;">' +
               '<div style="max-width:520px;margin:32px auto;background:#fff;border-radius:8px;' +
               'box-shadow:0 2px 8px rgba(0,0,0,0.08);overflow:hidden;">' +
               '<div style="background:#032d60;padding:24px 32px;">' +
               '<h2 style="color:#fff;margin:0;font-size:20px;">&#128197; Meeting Room Booked</h2>' +
               '<p style="color:#a8c4e0;margin:4px 0 0;font-size:13px;">Booking confirmation</p>' +
               '</div>' +
               '<div style="padding:28px 32px;">' +
               '<table style="width:100%;border-collapse:collapse;">' +
               '<tr><td style="padding:8px 0;color:#888;font-size:13px;width:120px;">Booking #</td>' +
               '<td style="padding:8px 0;font-weight:600;color:#111;">' + bookingName + '</td></tr>' +
               '<tr><td style="padding:8px 0;color:#888;font-size:13px;">Room</td>' +
               '<td style="padding:8px 0;font-weight:600;color:#111;">' + roomName + '</td></tr>' +
               '<tr><td style="padding:8px 0;color:#888;font-size:13px;">Employee</td>' +
               '<td style="padding:8px 0;color:#111;">' + employeeName + '</td></tr>' +
               '<tr><td style="padding:8px 0;color:#888;font-size:13px;">Start Time</td>' +
               '<td style="padding:8px 0;color:#111;">' + startStr + '</td></tr>' +
               '<tr><td style="padding:8px 0;color:#888;font-size:13px;">End Time</td>' +
               '<td style="padding:8px 0;color:#111;">' + endStr + '</td></tr>' +
               '</table>' +
               '<hr style="border:none;border-top:1px solid #eee;margin:20px 0;">' +
               '<p style="margin:0;font-size:14px;color:#444;">Click below to join the meeting:</p>' +
               joinButton +
               '<p style="margin:20px 0 0;font-size:12px;color:#aaa;">' +
               'This is an automated confirmation from Meeting Room Booking System.</p>' +
               '</div></div></body></html>';
    }
}