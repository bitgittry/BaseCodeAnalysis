DROP procedure IF EXISTS `PlayerGetAccessStatus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetAccessStatus`(clientID BIGINT)
BEGIN
  DECLARE clientStatID BIGINT DEFAULT -1;
  DECLARE sessionID BIGINT DEFAULT NULL;
  DECLARE depositRemaining, playRemaining DECIMAL(18,5) DEFAULT 0; 
  
  SET @clientID=clientID;
  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_id=@clientID AND is_active=1;
  SELECT session_id INTO sessionID FROM sessions_main WHERE (extra_id=clientID AND is_latest) AND status_code=1 AND session_type=2;

  SELECT TransactionGetRemainingDepositAmount(clientStatID) INTO depositRemaining;
  SELECT PlayLimitCheckRemainingAmount(sessionID, clientStatID) INTO playRemaining;

  SELECT account_activated, is_kyc_checked, kyc_checked_status_id, kyc_checked_date,
    is_test_player, test_player_allow_transfers, 
	IF(is_account_closed OR gaming_fraud_rule_client_settings.block_account, 1, 0) AS is_account_closed, 
    IFNULL(depositRemaining,gaming_payment_amounts.max_deposit) AS deposit_remaining, 
    IFNULL(playRemaining,gaming_payment_amounts.max_deposit) AS play_remaining,
	IFNULL(age_verification_types.name,'NotVerified') AS age_verification_type, 
    IF(gaming_clients.bonus_seeker OR gaming_fraud_rule_client_settings.bonus_seeker, 1, 0) AS bonus_seeker, 
    IF((IFNULL(chargebacks.ChargebacksCount, 0) - IFNULL(chargebacks.ReversalsCount,0)) = 0, 0, 1) AS has_chargebacks,
    gaming_client_registration_types.registration_type AS registration_type, gaming_client_registration_types.registration_code,
	gaming_player_statuses.player_status_name, closure_review_date
  FROM gaming_clients 
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_id = gaming_clients.client_id AND gaming_client_stats.client_stat_id = clientStatID
  STRAIGHT_JOIN gaming_payment_amounts ON  gaming_payment_amounts.currency_id = gaming_client_stats.currency_id 
  STRAIGHT_JOIN gaming_client_registrations ON gaming_client_registrations.client_id = gaming_clients.client_id AND gaming_client_registrations.is_current = 1
  STRAIGHT_JOIN gaming_client_registration_types ON gaming_client_registration_types.client_registration_type_id = gaming_client_registrations.client_registration_type_id 
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
  LEFT JOIN gaming_client_age_verification_types AS age_verification_types ON age_verification_types.client_age_verification_type_id=gaming_clients.age_verification_type_id
  LEFT JOIN gaming_player_statuses ON gaming_clients.player_status_id = gaming_player_statuses.player_status_id AND gaming_player_statuses.is_hidden = 0
  LEFT JOIN
  ( 
		SELECT chargeback_accounting.client_stat_id, 
			SUM(IF(chargeback_accounting.amount>0 AND chargeback_type.note_type='Chargeback', 0, 1)) AS 'ChargebacksCount',
            SUM(IF(chargeback_accounting.amount>0 AND chargeback_type.note_type='Chargeback Reversal', 0, 1)) AS 'ReversalsCount'
		FROM accounting_dc_notes AS chargeback_accounting FORCE INDEX (client_stat_id)
		STRAIGHT_JOIN accounting_dc_note_types AS chargeback_type ON chargeback_accounting.dc_note_type_id = chargeback_type.dc_note_type_id 
			AND chargeback_type.note_type IN ('Chargeback Reversal','Chargeback') 
        WHERE chargeback_accounting.client_stat_id = clientStatID AND chargeback_accounting.balance_history_id IS NOT NULL
		GROUP BY chargeback_accounting.client_stat_id
  ) AS chargebacks ON chargebacks.client_stat_id = gaming_client_stats.client_stat_id
  WHERE gaming_clients.client_id=clientID;
  
  SELECT status_type, status_description, allow_login, allow_play, allow_transfers, allow_deposits
  FROM
  (
    SELECT 'Account_Info' AS status_type, 
		IF(is_active=0 OR is_play_allowed=0 OR is_suspicious OR exceeded_login_attempts=1 OR deposit_allowed=0 OR withdrawal_allowed=0, 'Restricted','No Restrictions') AS status_description, 
        (is_active AND !exceeded_login_attempts) AS allow_login, is_play_allowed AS allow_play, 
        ((NOT is_suspicious) AND deposit_allowed AND withdrawal_allowed) AS allow_transfers, 
        ((NOT is_suspicious) AND deposit_allowed) AS allow_deposits
    FROM gaming_clients 
    WHERE client_id=clientID
  ) AS X1
  UNION ALL
  (
    SELECT 'Player_Restriction' AS status_type, 
		IF (COUNT(*)>0, 'Restricted','No Restrictions'), IFNULL(SUM(disallow_login)=0, 1) AS allow_login, IFNULL(SUM(disallow_play)=0, 1) AS allow_play, 
        IFNULL(SUM(IF(disallow_transfers OR disallow_deposits OR disallow_withdrawals, 1, 0))=0, 1) AS allow_transfers, 
        IFNULL(SUM(IF(disallow_transfers OR disallow_deposits, 1, 0))=0, 1) AS allow_deposits
    FROM gaming_player_restrictions FORCE INDEX (client_active_non_expired)
    STRAIGHT_JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND 
		gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
    WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date
  ) 
  UNION ALL
  (
    SELECT 'Fraud_Restriction' AS status_type, IFNULL(class_type.description, 'Safe') as description, 
		IFNULL(SUM(disallow_login)=0, 1) AS allow_login, IFNULL(SUM(disallow_play)=0, 1) AS allow_play, 
        IFNULL(SUM(disallow_transfers)=0, 1) AS allow_transfers, IFNULL(SUM(disallow_transfers)=0, 1) AS allow_deposits
    FROM gaming_fraud_client_events AS cl_events FORCE INDEX (client_id_current_event)
    STRAIGHT_JOIN gaming_fraud_classification_types AS class_type ON cl_events.fraud_classification_type_id=class_type.fraud_classification_type_id
    WHERE cl_events.client_id=clientID AND cl_events.is_current=1
  );
 
	SELECT ROW_TYPE,user_has_pin,is_indefinitely
	FROM 
	(
		SELECT 0 AS ROW_TYPE, IF(authentication_pin is null ,0,1) AS user_has_pin , null as is_indefinitely
		FROM gaming_clients gc
		WHERE client_id = clientID
	) AS pin_restrictions
	UNION ALL
	(
		SELECT 1 AS ROW_TYPE, null as user_has_pin, is_indefinitely
		FROM gaming_player_restrictions gpr FORCE INDEX (client_active_non_expired)
		LEFT JOIN gaming_clients gc ON gpr.client_id=gc.client_id AND gc.authentication_pin IS NOT NULL
		WHERE gpr.client_id = clientID AND gpr.is_active=1 AND gpr.player_restriction_type_id=5 AND gpr.restrict_until_date > NOW() 
	);
  
  CALL PlayerRestrictionGetAllRestrictions(clientID, 0);
  
END$$

DELIMITER ;

