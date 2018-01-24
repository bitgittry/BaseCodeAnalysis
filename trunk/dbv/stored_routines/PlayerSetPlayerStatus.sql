DROP PROCEDURE IF EXISTS `PlayerSetPlayerStatus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSetPlayerStatus`(
			accountActivated bool, 
			isPlayAllowed bool, 
			isKYCChecked bool, 
			depositAllowed bool, 
			testPlayerAllowTransfers bool,
			isTestPlayer bool,
			bonusSeeker bool,
			bonusDontWant bool,
			isSuspicious bool,
			withdrawalAllowed bool,
			riskScore bigint,
			registrationType varchar(50),
			accountClosed bool,
			ageVerification varchar(50),
			fullyRegistered bool,
			kycCheckedStatus varchar(50),
			pendingClosure bool,
			pinEnabled bool,
			transferAllowed bool,
			loginAllowed bool,
			clientID BIGINT 
)
BEGIN

DECLARE auditLogGroupId BIGINT;
DECLARE curPlayerStatusId BIGINT(20) DEFAULT NULL;
DECLARE newPlayerStatusId BIGINT(20) DEFAULT NULL;
DECLARE curPlayerStatusName varchar(50);
DECLARE newPlayerStatusName varchar(50);

		select gaming_player_statuses.player_status_id, gaming_player_statuses.player_status_name into curPlayerStatusId, curPlayerStatusName  from gaming_clients 
        JOIN gaming_player_statuses ON gaming_clients.player_status_id = gaming_player_statuses.player_status_id
        WHERE client_id = clientID;

		select status, status_name into newPlayerStatusId, newPlayerStatusName from 
		(
		SELECT gaming_player_statuses.player_status_id as status, gaming_player_statuses.player_status_name as status_name
		FROM gaming_player_status_attributes_values
		JOIN gaming_player_statuses ON gaming_player_status_attributes_values.player_status_id = gaming_player_statuses.player_status_id
		JOIN gaming_player_status_attributes ON gaming_player_status_attributes_values.player_status_attribute_id = gaming_player_status_attributes.attribute_id
		WHERE
			CASE status_condition 
			WHEN 'AND' THEN
			IF (attribute_name = 'account_activated', ( IF(operator = '=', IF(value = 'true', accountActivated = 1, accountActivated = 0), IF(value = 'true', accountActivated != 1, accountActivated != 0))), 1=1)
			AND IF (attribute_name = 'is_play_allowed', ( IF(operator = '=', IF(value = 'true', isPlayAllowed = 1, isPlayAllowed = 0), IF(value = 'true', isPlayAllowed != 1, isPlayAllowed != 0))), 1=1)
			AND IF (attribute_name = 'is_kyc_checked', ( IF(operator = '=', IF(value = 'true', isKYCChecked = 1, isKYCChecked = 0), IF(value = 'true', isKYCChecked != 1, isKYCChecked != 0))), 1=1)
			AND IF (attribute_name = 'deposit_allowed', ( IF(operator = '=', IF(value = 'true', depositAllowed = 1, depositAllowed = 0), IF(value = 'true', depositAllowed != 1, depositAllowed != 0))), 1=1)
			AND IF (attribute_name = 'test_player_allow_transfers', ( IF(operator = '=', IF(value = 'true', testPlayerAllowTransfers = 1, testPlayerAllowTransfers = 0), IF(value = 'true', testPlayerAllowTransfers != 1, testPlayerAllowTransfers != 0))), 1=1)
			AND IF (attribute_name = 'is_test_player', ( IF(operator = '=', IF(value = 'true', isTestPlayer = 1, isTestPlayer = 0), IF(value = 'true', isTestPlayer != 1, isTestPlayer != 0))), 1=1)
			AND IF (attribute_name = 'bonus_seeker', ( IF(operator = '=', IF(value = 'true', bonusSeeker = 1, bonusSeeker = 0), IF(value = 'true', bonusSeeker != 1, bonusSeeker != 0))), 1=1)
			AND IF (attribute_name = 'bonus_dont_want', ( IF(operator = '=', IF(value = 'true', bonusDontWant = 1, bonusDontWant = 0), IF(value = 'true', bonusDontWant != 1, bonusDontWant != 0))), 1=1)
			AND IF (attribute_name = 'is_suspicious', ( IF(operator = '=', IF(value = 'true', isSuspicious = 1, isSuspicious = 0), IF(value = 'true', isSuspicious != 1, isSuspicious != 0))), 1=1)
			AND IF (attribute_name = 'withdrawal_allowed', ( IF(operator = '=', IF(value = 'true', withdrawalAllowed = 1, withdrawalAllowed = 0), IF(value = 'true', withdrawalAllowed != 1, withdrawalAllowed != 0))), 1=1)
			AND IF (attribute_name = 'risk_score', IF(operator = '=', riskScore = CAST(value AS DECIMAL(18,5)), IF(operator = '!=',   riskScore != CAST(value AS DECIMAL(18,5)), IF(operator = '<', riskScore < CAST(value AS DECIMAL(18,5)), IF(operator = '<=',  riskScore <= CAST(value AS DECIMAL(18,5)),IF(operator = '>',  riskScore > CAST(value AS DECIMAL(18,5)),IF(operator = '>=',  riskScore >= CAST(value AS DECIMAL(18,5)), 1=0)))))),1=1)
			AND IF (attribute_name = 'client_registration_code', ( IF(operator = '=', registrationType = value, IF(operator = '!=',  registrationType != value, 1=0))),1=1)
			AND IF (attribute_name = 'login_allowed', ( IF(operator = '=', IF(value = 'true', loginAllowed = 1, loginAllowed = 0), IF(value = 'true', loginAllowed != 1, loginAllowed != 0))), 1=1)
			AND IF (attribute_name = 'transfer_allowed', ( IF(operator = '=', IF(value = 'true', transferAllowed = 1, transferAllowed = 0), IF(value = 'true', transferAllowed != 1, transferAllowed != 0))), 1=1)
			AND IF (attribute_name = 'pin_enabled', ( IF(operator = '=', IF(value = 'true', pinEnabled = 1, pinEnabled = 0), IF(value = 'true', pinEnabled != 1, pinEnabled != 0))), 1=1)
			AND IF (attribute_name = 'account_closed', ( IF(operator = '=', IF(value = 'true', accountClosed = 1, accountClosed = 0), IF(value = 'true', accountClosed != 1, accountClosed != 0))), 1=1)
			AND IF (attribute_name = 'has_chargebacks', ( IF(operator = '=', IF(value = 'true', (SELECT (chargeback_count > 0) FROM gaming_client_stats WHERE client_id = clientID),(SELECT (chargeback_count = 0) FROM gaming_client_stats WHERE client_id = clientID)), 1=0)),1=1)
			AND IF (attribute_name = 'age_verification', ( IF(operator = '=', ageVerification = value, IF(operator = '!=',  ageVerification != value, 1=0))),1=1)
			AND IF (attribute_name = 'fully_registered_player', ( IF(operator = '=', IF(value = 'true', fullyRegistered = 1, fullyRegistered = 0), IF(value = 'true', fullyRegistered != 1, fullyRegistered != 0))), 1=1)
			AND IF (attribute_name = 'kyc_checked_status', ( IF(operator = '=', kycCheckedStatus = value, IF(operator = '!=',  kycCheckedStatus != value, 1=0))),1=1)
			AND IF (attribute_name = 'pending_closure', ( IF(operator = '=', IF(value = 'true', pendingClosure = 1, pendingClosure = 0), IF(value = 'true', pendingClosure != 1, pendingClosure != 0))), 1=1)
			
			WHEN 'OR' THEN
			IF (attribute_name = 'account_activated', ( IF(operator = '=', IF(value = 'true', accountActivated = 1, accountActivated = 0), IF(value = 'true', accountActivated != 1, accountActivated != 0))), 1=0)
			OR IF (attribute_name = 'is_play_allowed', ( IF(operator = '=', IF(value = 'true', isPlayAllowed = 1, isPlayAllowed = 0), IF(value = 'true', isPlayAllowed != 1, isPlayAllowed != 0))), 1=0)
			OR IF (attribute_name = 'is_kyc_checked', ( IF(operator = '=', IF(value = 'true', isKYCChecked = 1, isKYCChecked = 0), IF(value = 'true', isKYCChecked != 1, isKYCChecked != 0))), 1=0)
			OR IF (attribute_name = 'deposit_allowed', ( IF(operator = '=', IF(value = 'true', depositAllowed = 1, depositAllowed = 0), IF(value = 'true', depositAllowed != 1, depositAllowed != 0))), 1=0)
			OR IF (attribute_name = 'test_player_allow_transfers', ( IF(operator = '=', IF(value = 'true', testPlayerAllowTransfers = 1, testPlayerAllowTransfers = 0), IF(value = 'true', testPlayerAllowTransfers != 1, testPlayerAllowTransfers != 0))), 1=0)
			OR IF (attribute_name = 'is_test_player', ( IF(operator = '=', IF(value = 'true', isTestPlayer = 1, isTestPlayer = 0), IF(value = 'true', isTestPlayer != 1, isTestPlayer != 0))), 1=0)
			OR IF (attribute_name = 'bonus_seeker', ( IF(operator = '=', IF(value = 'true', bonusSeeker = 1, bonusSeeker = 0), IF(value = 'true', bonusSeeker != 1, bonusSeeker != 0))), 1=0)
			OR IF (attribute_name = 'bonus_dont_want', ( IF(operator = '=', IF(value = 'true', bonusDontWant = 1, bonusDontWant = 0), IF(value = 'true', bonusDontWant != 1, bonusDontWant != 0))), 1=0)
			OR IF (attribute_name = 'is_suspicious', ( IF(operator = '=', IF(value = 'true', isSuspicious = 1, isSuspicious = 0), IF(value = 'true', isSuspicious != 1, isSuspicious != 0))), 1=0)
			OR IF (attribute_name = 'withdrawal_allowed', ( IF(operator = '=', IF(value = 'true', withdrawalAllowed = 1, withdrawalAllowed = 0), IF(value = 'true', withdrawalAllowed != 1, withdrawalAllowed != 0))), 1=0)
			OR IF (attribute_name = 'risk_score', IF(operator = '=', riskScore = CAST(value AS DECIMAL(18,5)), IF(operator = '!=',   riskScore != CAST(value AS DECIMAL(18,5)), IF(operator = '<', riskScore < CAST(value AS DECIMAL(18,5)), IF(operator = '<=',  riskScore <= CAST(value AS DECIMAL(18,5)),IF(operator = '>',  riskScore > CAST(value AS DECIMAL(18,5)),IF(operator = '>=',  riskScore >= CAST(value AS DECIMAL(18,5)), 1=0)))))),1=0)
			OR IF (attribute_name = 'client_registration_code', ( IF(operator = '=', registrationType = value, IF(operator = '!=',  registrationType != value, 1=0))),1=0)
			OR IF (attribute_name = 'login_allowed', ( IF(operator = '=', IF(value = 'true', loginAllowed = 1, loginAllowed = 0), IF(value = 'true', loginAllowed != 1, loginAllowed != 0))), 1=0)
			OR IF (attribute_name = 'transfer_allowed', ( IF(operator = '=', IF(value = 'true', transferAllowed = 1, transferAllowed = 0), IF(value = 'true', transferAllowed != 1, transferAllowed != 0))), 1=0)
			OR IF (attribute_name = 'pin_enabled', ( IF(operator = '=', IF(value = 'true', pinEnabled = 1, pinEnabled = 0), IF(value = 'true', pinEnabled != 1, pinEnabled != 0))), 1=0)
			OR IF (attribute_name = 'account_closed', ( IF(operator = '=', IF(value = 'true', accountClosed = 1, accountClosed = 0), IF(value = 'true', accountClosed != 1, accountClosed != 0))), 1=0)
			OR IF (attribute_name = 'has_chargebacks', ( IF(operator = '=', IF(value = 'true', (SELECT (chargeback_count > 0) FROM gaming_client_stats WHERE client_id = clientID),(SELECT (chargeback_count = 0) FROM gaming_client_stats WHERE client_id = clientID)), 1=0)),1=0)
			OR IF (attribute_name = 'age_verification', ( IF(operator = '=', ageVerification = value, IF(operator = '!=',  ageVerification != value, 1=0))),1=0)						
			OR IF (attribute_name = 'fully_registered_player', ( IF(operator = '=', IF(value = 'true', fullyRegistered = 1, fullyRegistered = 0), IF(value = 'true', fullyRegistered != 1, fullyRegistered != 0))), 1=0)
			OR IF (attribute_name = 'kyc_checked_status', ( IF(operator = '=', kycCheckedStatus = value, IF(operator = '!=',  kycCheckedStatus != value, 1=0))),1=0)
			OR IF (attribute_name = 'pending_closure', ( IF(operator = '=', IF(value = 'true', pendingClosure = 1, pendingClosure = 0), IF(value = 'true', pendingClosure != 1, pendingClosure != 0))), 1=0)

			END
			AND gaming_player_status_attributes_values.is_hidden = 0
			AND gaming_player_statuses.is_hidden = 0

			GROUP BY gaming_player_statuses.player_status_id
		
			HAVING IF((SELECT status_condition FROM gaming_player_statuses WHERE player_status_id = status) = 'AND',COUNT(gaming_player_statuses.player_status_id) = 
			(SELECT COUNT(*) FROM gaming_player_status_attributes_values 
			WHERE is_hidden = 0 AND player_status_id = status                    
			GROUP BY player_status_id  ),1=1)

			ORDER BY gaming_player_statuses.priority
			LIMIT 1                    
		) as player_statuses;	                
                    
		               

		if (ifnull(curPlayerStatusId, -1) != ifnull(newPlayerStatusId,-1)) THEN
        
			UPDATE gaming_clients SET player_status_id = newPlayerStatusId WHERE client_id = clientID; 
            
			SET auditLogGroupId = AuditLogNewGroup(0, NULL, clientID, 12, 'System' , NULL, NULL, clientID);
			CALL AuditLogAttributeChange('Player Status Changed', clientID, auditLogGroupId, newPlayerStatusName, curPlayerStatusName, NOW());
		END IF;
END$$

DELIMITER ;

