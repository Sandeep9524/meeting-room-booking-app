public with sharing class GoogleMeetService {

    // ── Build JWT for Google OAuth (Service Account) ──────────────────────────
    private static String buildJWT(Google_Config__mdt cfg) {
        // Header
        String header = JSON.serialize(new Map<String,String>{
            'alg' => 'RS256', 'typ' => 'JWT'
        });

        // Claims
        Long now = DateTime.now().getTime() / 1000;
        Map<String,Object> claims = new Map<String,Object>{
            'iss'   => cfg.Client_Email__c,
            'scope' => 'https://www.googleapis.com/auth/calendar',
            'aud'   => 'https://oauth2.googleapis.com/token',
            'iat'   => now,
            'exp'   => now + 3600
        };

        String headerEncoded  = base64UrlEncode(Blob.valueOf(header));
        String claimsEncoded  = base64UrlEncode(Blob.valueOf(JSON.serialize(claims)));
        String signingInput   = headerEncoded + '.' + claimsEncoded;

        // Sign with RSA-SHA256 using the private key
        String privateKey = cfg.Private_Key__c
            .replace('-----BEGIN RSA PRIVATE KEY-----', '')
            .replace('-----END RSA PRIVATE KEY-----', '')
            .replace('-----BEGIN PRIVATE KEY-----', '')
            .replace('-----END PRIVATE KEY-----', '')
            .replace('\n', '')
            .replace('\r', '')
            .replaceAll('\\s', '');

        Blob privateKeyBlob = EncodingUtil.base64Decode(privateKey);
        Blob signedBlob     = Crypto.sign('RSA-SHA256',
            Blob.valueOf(signingInput), privateKeyBlob);
        String signature    = base64UrlEncode(signedBlob);

        return signingInput + '.' + signature;
    }

    // ── Base64 URL encode (no padding) ────────────────────────────────────────
    private static String base64UrlEncode(Blob input) {
        return EncodingUtil.base64Encode(input)
            .replace('+', '-')
            .replace('/', '_')
            .replace('=', '');
    }

    // ── Get OAuth access token from Google ────────────────────────────────────
    private static String getAccessToken(Google_Config__mdt cfg) {
        String jwt = buildJWT(cfg);

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://oauth2.googleapis.com/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(
            'grant_type=' + EncodingUtil.urlEncode(
                'urn:ietf:params:oauth:grant-type:jwt-bearer', 'UTF-8') +
            '&assertion=' + jwt
        );
        req.setTimeout(20000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new CalloutException(
                'Google token failed: ' + res.getStatusCode() + ' ' + res.getBody());
        }

        Map<String,Object> data =
            (Map<String,Object>) JSON.deserializeUntyped(res.getBody());
        return (String) data.get('access_token');
    }

    // ── Main: create Google Calendar event with Meet link ─────────────────────
    @future(callout=true)
    public static void createMeetingLink(Id bookingId) {
        try {
            Booking__c booking = [
                SELECT Id, Employee_Name__c, Start_Time__c, End_Time__c,
                       Room_Name__r.Name
                FROM Booking__c
                WHERE Id = :bookingId LIMIT 1
            ];

            Google_Config__mdt cfg = [
                SELECT Client_Email__c, Private_Key__c, Calendar_ID__c
                FROM Google_Config__mdt
                WHERE DeveloperName = 'Default' LIMIT 1
            ];

            String accessToken = getAccessToken(cfg);

            // Format times as ISO 8601 UTC
            String startISO = booking.Start_Time__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            String endISO   = booking.End_Time__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

            String roomName = booking.Room_Name__r != null
                ? booking.Room_Name__r.Name : 'Meeting Room';

            // Build Calendar event with conferenceData to generate Meet link
            Map<String,Object> eventBody = new Map<String,Object>{
                'summary'     => roomName + ' — ' + booking.Employee_Name__c,
                'description' => 'Booking created via Meeting Room Booking System',
                'start'       => new Map<String,String>{
                    'dateTime' => startISO, 'timeZone' => 'UTC'},
                'end'         => new Map<String,String>{
                    'dateTime' => endISO,   'timeZone' => 'UTC'},
                'conferenceData' => new Map<String,Object>{
                    'createRequest' => new Map<String,Object>{
                        'requestId'             => bookingId,
                        'conferenceSolutionKey' => new Map<String,String>{
                            'type' => 'eventHangout'
                        }
                    }
                }
            };

            HttpRequest calReq = new HttpRequest();
            // conferenceDataVersion=1 tells Google to generate the Meet link
            calReq.setEndpoint(
                'https://www.googleapis.com/calendar/v3/calendars/' +
                EncodingUtil.urlEncode(cfg.Calendar_ID__c, 'UTF-8') +
                '/events?conferenceDataVersion=1'
            );
            calReq.setMethod('POST');
            calReq.setHeader('Authorization', 'Bearer ' + accessToken);
            calReq.setHeader('Content-Type', 'application/json');
            calReq.setBody(JSON.serialize(eventBody));
            calReq.setTimeout(20000);

            HttpResponse calRes = new Http().send(calReq);

            if (calRes.getStatusCode() == 200 || calRes.getStatusCode() == 201) {
                Map<String,Object> eventData =
                    (Map<String,Object>) JSON.deserializeUntyped(calRes.getBody());

                // Extract Meet link from conferenceData
                String meetLink = extractMeetLink(eventData);

                if (String.isNotBlank(meetLink)) {
                    update new Booking__c(
                        Id = bookingId,
                        Meeting_Link__c = meetLink
                    );
                    System.debug('Meet link created: ' + meetLink);
                }
            } else {
                System.debug('Calendar event failed: ' +
                    calRes.getStatusCode() + ' ' + calRes.getBody());
            }

        } catch (Exception e) {
            System.debug('GoogleMeetService error: ' + e.getMessage() +
                         '\n' + e.getStackTraceString());
        }
    }

    // ── Extract Meet link from Calendar API response ──────────────────────────
    private static String extractMeetLink(Map<String,Object> eventData) {
        try {
            Map<String,Object> confData =
                (Map<String,Object>) eventData.get('conferenceData');
            if (confData == null) return null;

            List<Object> entryPoints =
                (List<Object>) confData.get('entryPoints');
            if (entryPoints == null) return null;

            for (Object ep : entryPoints) {
                Map<String,Object> entry = (Map<String,Object>) ep;
                if ('video'.equals((String) entry.get('entryPointType'))) {
                    return (String) entry.get('uri');
                }
            }
        } catch (Exception e) {
            System.debug('extractMeetLink error: ' + e.getMessage());
        }
        return null;
    }
}