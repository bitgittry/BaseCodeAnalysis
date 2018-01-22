DROP procedure IF EXISTS `PlayerUpdatePromotionalFlags`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdatePromotionalFlags`(userID BIGINT, sessionID BIGINT, clientID BIGINT, 
  promoByEmail TINYINT(1), promoBySMS TINYINT(1), promoByPost TINYINT(1), promoByPhone TINYINT(1), promoByMobile TINYINT(1), promoByThirdParty TINYINT(1), 
  emailVerificationTypeID TINYINT(4), smsVerificationTypeID TINYINT(4), postVerificationTypeID TINYINT(4), phoneVerificationTypeID TINYINT(4), thirdPartyVerificationTypeID TINYINT(4), preferredPromotionTypeID INT(11), 
  newsFeedsAllow TINYINT(1), forceUpdateDetails TINYINT(1), INOUT changeDetected TINYINT(1))
BEGIN 
  -- Added push notification
  
  DECLARE curPromoByEmail, curPromoBySMS, curPromoByPost, curPromoByPhone, curPromoByMobile, curPromoByThirdParty, curNewsFeedsAllow TINYINT(1) DEFAULT 0;
  DECLARE curEmailVerificationTypeID, curSMSVerificationTypeID, curPostVerificationTypeID, curPhoneVerificationTypeID, curThirdPartyVerificationTypeID TINYINT(4) DEFAULT 1;
  DECLARE curPreferredPromotionTypeID INT(11) DEFAULT 1;
  DECLARE changeNo INT DEFAULT NULL;
  DECLARE modifierEntityId, auditLogGroupId BIGINT DEFAULT -1;
  DECLARE modifierEntityType VARCHAR(45); 

  SET modifierEntityType = IFNULL(@modifierEntityType, 'System');
  SET userID=IFNULL(userID, 0);

    -- New version of audit logs
  
	  SELECT 
		receive_promotional_by_email, receive_promotional_by_sms, receive_promotional_by_post, receive_promotional_by_phone, receive_promotional_by_mobile, receive_promotional_by_third_party,
		email_verification_type_id, sms_verification_type_id, post_verification_type_id, phone_verification_type_id, third_party_verification_type_id,
		preferred_promotion_type_id, news_feeds_allow, num_details_changes+1
	  INTO 
		curPromoByEmail, curPromoBySMS, curPromoByPost, curPromoByPhone, curPromoByMobile, curPromoByThirdParty,
		curEmailVerificationTypeID, curSMSVerificationTypeID, curPostVerificationTypeID, curPhoneVerificationTypeID, curThirdPartyVerificationTypeID,
		curPreferredPromotionTypeID, curNewsFeedsAllow, changeNo
	  FROM gaming_clients WHERE client_id=clientID;
	  
	  IF (promoByEmail IS NOT NULL) THEN
		IF (curPromoByEmail!=promoByEmail) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Promo By Email', promoByEmail, curPromoByEmail, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Promo By Email', clientID, auditLogGroupId, promoByEmail, curPromoByEmail, NOW());
		END IF;
	  END IF;
	  IF (promoBySMS IS NOT NULL) THEN
		IF (curPromoBySMS!=promoBySMS) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Promo By SMS', promoBySMS, curPromoBySMS, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Promo By SMS', clientID, auditLogGroupId, promoBySMS, curPromoBySMS, NOW());
		END IF;
	  END IF;
	  IF (promoByPost IS NOT NULL) THEN
		IF (curPromoByPost!=promoByPost) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Promo By Post', promoByPost, curPromoByPost, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Promo By Post', clientID, auditLogGroupId, promoByPost, curPromoByPost, NOW());
		END IF;
	  END IF;
	  IF (promoByPhone IS NOT NULL) THEN
		IF (curPromoByPhone!=promoByPhone) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Promo By Phone', promoByPhone, curPromoByPhone, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Promo By Phone', clientID, auditLogGroupId, promoByPhone, curPromoByPhone, NOW());
		END IF;
	  END IF;
	  IF (promoByMobile IS NOT NULL) THEN
		IF (curPromoByMobile!=promoByMobile) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Promo By Mobile', promoByMobile, curPromoByMobile, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Promo By Mobile', clientID, auditLogGroupId, promoByMobile, curPromoByMobile, NOW());
		END IF;
	  END IF;
	  IF (promoByThirdParty IS NOT NULL) THEN
		IF (curPromoByThirdParty!=promoByThirdParty) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Promo By Third Party', promoByThirdParty, curPromoByThirdParty, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Promo By Third Party', clientID, auditLogGroupId, promoByThirdParty, curPromoByThirdParty, NOW());
		END IF;
	  END IF;	
	  
	  IF (emailVerificationTypeID IS NOT NULL) THEN
		IF (curEmailVerificationTypeID!=emailVerificationTypeID) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Email Verification', ClientGetVerificationTypeString(emailVerificationTypeID), ClientGetVerificationTypeString(curEmailVerificationTypeID), changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Email Verification', clientID, auditLogGroupId, ClientGetVerificationTypeString(emailVerificationTypeID), ClientGetVerificationTypeString(curEmailVerificationTypeID), NOW());
		END IF;
	  END IF;
	  IF (smsVerificationTypeID IS NOT NULL) THEN
		IF (curSMSVerificationTypeID!=smsVerificationTypeID) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'SMS Verification', ClientGetVerificationTypeString(smsVerificationTypeID), ClientGetVerificationTypeString(curSMSVerificationTypeID), changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('SMS Verification', clientID, auditLogGroupId, ClientGetVerificationTypeString(smsVerificationTypeID), ClientGetVerificationTypeString(curSMSVerificationTypeID), NOW());
		END IF;
	  END IF;
	  IF (postVerificationTypeID IS NOT NULL) THEN
		IF (curPostVerificationTypeID!=postVerificationTypeID) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Post Verification', ClientGetVerificationTypeString(postVerificationTypeID), ClientGetVerificationTypeString(curPostVerificationTypeID), changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Post Verification', clientID, auditLogGroupId, ClientGetVerificationTypeString(postVerificationTypeID), ClientGetVerificationTypeString(curPostVerificationTypeID), NOW());
		END IF;
	  END IF;
	  IF (phoneVerificationTypeID IS NOT NULL) THEN
		IF (curPhoneVerificationTypeID!=phoneVerificationTypeID) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Phone Verification', ClientGetVerificationTypeString(phoneVerificationTypeID), ClientGetVerificationTypeString(curPhoneVerificationTypeID), changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Phone Verification', clientID, auditLogGroupId, ClientGetVerificationTypeString(phoneVerificationTypeID), ClientGetVerificationTypeString(curPhoneVerificationTypeID), NOW());
		END IF;
	  END IF;
	  IF (thirdPartyVerificationTypeID IS NOT NULL) THEN
		IF (curThirdPartyVerificationTypeID!=thirdPartyVerificationTypeID) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Third Party Verification', ClientGetVerificationTypeString(thirdPartyVerificationTypeID), ClientGetVerificationTypeString(curThirdPartyVerificationTypeID), changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Third Party Verification', clientID, auditLogGroupId, ClientGetVerificationTypeString(thirdPartyVerificationTypeID), ClientGetVerificationTypeString(curThirdPartyVerificationTypeID), NOW());
		END IF;
	  END IF;		
	  
	  IF (preferredPromotionTypeID IS NOT NULL) THEN
		IF (curPreferredPromotionTypeID!=preferredPromotionTypeID) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'Preferred Promotion', 
				CASE preferredPromotionTypeID
				   WHEN 2 THEN 'Email'
				   WHEN 3 THEN 'SMS'
				   WHEN 4 THEN 'Post'
				   WHEN 5 THEN 'Phone'
				   WHEN 6 THEN 'Third Pary'
				   WHEN 7 THEN 'Mobile'
				   ELSE 'Unknown'
				END,
				CASE curPreferredPromotionTypeID
				   WHEN 2 THEN 'Email'
				   WHEN 3 THEN 'SMS'
				   WHEN 4 THEN 'Post'
				   WHEN 5 THEN 'Phone'
				   WHEN 6 THEN 'Third Pary'
				   WHEN 7 THEN 'Mobile'
				   ELSE 'Unknown'
				END, changeNo
			);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('Preferred Promotion', clientID, auditLogGroupId, CASE preferredPromotionTypeID
				   WHEN 2 THEN 'Email'
				   WHEN 3 THEN 'SMS'
				   WHEN 4 THEN 'Post'
				   WHEN 5 THEN 'Phone'
				   WHEN 6 THEN 'Third Pary'
				   WHEN 7 THEN 'Mobile'
				   ELSE 'Unknown'
				END,
				CASE curPreferredPromotionTypeID
				   WHEN 2 THEN 'Email'
				   WHEN 3 THEN 'SMS'
				   WHEN 4 THEN 'Post'
				   WHEN 5 THEN 'Phone'
				   WHEN 6 THEN 'Third Pary'
				   WHEN 7 THEN 'Mobile'
				   ELSE 'Unknown'
				END, NOW());
		END IF;
	  END IF;	
	  
	  IF (newsFeedsAllow IS NOT NULL) THEN
		IF (curNewsFeedsAllow!=newsFeedsAllow) THEN
			SET changeDetected = 1;
			INSERT INTO gaming_client_changes (client_id, user_id, timestamp, attr_name, attr_value, attr_value_before, change_no)
			VALUES (clientID, userID, now(), 'News Feeds', newsFeedsAllow, curNewsFeedsAllow, changeNo);
			IF(auditLogGroupId = -1) THEN
				SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 2, modifierEntityType, NULL, NULL, clientID);
			END IF;
			CALL AuditLogAttributeChange('News Feeds', clientID, auditLogGroupId, newsFeedsAllow, curNewsFeedsAllow, NOW());
		END IF;
	  END IF;

  IF (IFNULL(forceUpdateDetails, 0) = 1)
  THEN
	  UPDATE gaming_clients 
	  SET 
		receive_promotional_by_email=IFNULL(promoByEmail, receive_promotional_by_email), receive_promotional_by_sms=IFNULL(promoBySMS, receive_promotional_by_sms), receive_promotional_by_post=IFNULL(promoByPost, receive_promotional_by_post), receive_promotional_by_phone=IFNULL(promoByPhone, receive_promotional_by_phone), receive_promotional_by_mobile=IFNULL(promoByMobile, receive_promotional_by_mobile), receive_promotional_by_third_party=IFNULL(promoByThirdParty, receive_promotional_by_third_party), 
		email_verification_type_id=IFNULL(emailVerificationTypeID, email_verification_type_id), sms_verification_type_id=IFNULL(smsVerificationTypeID, sms_verification_type_id), post_verification_type_id=IFNULL(postVerificationTypeID, post_verification_type_id), 
		phone_verification_type_id=IFNULL(phoneVerificationTypeID, phone_verification_type_id), third_party_verification_type_id=IFNULL(thirdPartyVerificationTypeID, third_party_verification_type_id), 
		preferred_promotion_type_id=IFNULL(preferredPromotionTypeID, preferred_promotion_type_id), news_feeds_allow=IFNULL(newsFeedsAllow, news_feeds_allow),
		session_id=sessionID, last_updated=NOW(), num_details_changes=IF(changeDetected, changeNo, num_details_changes)
	  WHERE client_id=clientID;
  END IF;

  CALL NotificationEventCreate(3, clientID, NULL, 0);
  CALL NotificationEventCreate(614, clientID, NULL, 0);
  
END$$

DELIMITER ;

