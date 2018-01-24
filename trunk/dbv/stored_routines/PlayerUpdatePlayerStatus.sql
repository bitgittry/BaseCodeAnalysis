DROP procedure IF EXISTS `PlayerUpdatePlayerStatus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdatePlayerStatus`(clientID BIGINT)
root: BEGIN

	DECLARE accountActivated TINYINT(1) DEFAULT 0;
	DECLARE isPlayAllowed TINYINT(1) DEFAULT 0;
	DECLARE isKYCChecked TINYINT(1) DEFAULT 0;
	DECLARE depositAllowed TINYINT(1) DEFAULT 0; 
	DECLARE testPlayerAllowTransfers TINYINT(1) DEFAULT 0;
	DECLARE isTestPlayer TINYINT(1) DEFAULT 0;
	DECLARE bonusSeeker TINYINT(1) DEFAULT 0;
	DECLARE bonusDontWant TINYINT(1) DEFAULT 0;
	DECLARE isSuspicious TINYINT(1) DEFAULT 0;
	DECLARE withdrawalAllowed TINYINT(1) DEFAULT 0;
	DECLARE riskScore bigint;
	DECLARE registrationType varchar(50);
	DECLARE accountClosed TINYINT(1) DEFAULT 0;
	DECLARE ageVerification varchar(50);
	DECLARE fullyRegistered TINYINT(1) DEFAULT 0;
	DECLARE kycCheckedStatus varchar(50);
	DECLARE pendingClosure TINYINT(1) DEFAULT 0;
	DECLARE pinEnabled TINYINT(1) DEFAULT 0;
	DECLARE transferAllowed TINYINT(1) DEFAULT 0;
	DECLARE loginAllowed TINYINT(1) DEFAULT 0;
			
	SELECT
	gaming_clients.is_account_closed, 
	gaming_clients.account_activated, 
	gaming_clients.is_play_allowed, 
	gaming_clients.is_kyc_checked,  
	gaming_clients.deposit_allowed, 
	gaming_clients.test_player_allow_transfers, 
	gaming_clients.is_test_player,
	gaming_clients.bonus_seeker, 
	gaming_clients.bonus_dont_want, 
	gaming_clients.is_suspicious, 
	gaming_clients.withdrawal_allowed, 
	gaming_clients.risk_score, 
	gaming_client_registration_types.registration_code AS registrationType,
	IF(gaming_client_registration_types.client_registration_type_id = 3 /* FULL */,1,0) AS fullyRegistered,
	IFNULL(gaming_kyc_checked_statuses.status_name,'') AS kycCheckedStatus, 
	age_verification_types.name AS ageVerification, 
	IF(closure_review_date IS NULL,0,1) AS pendingClosure
	INTO
	accountClosed, 
	accountActivated, 
	isPlayAllowed, 
	isKYCChecked, 
	depositAllowed, 
	testPlayerAllowTransfers,
	isTestPlayer,
	bonusSeeker, 
	bonusDontWant, 
	isSuspicious, 
	withdrawalAllowed, 
	riskScore, 
	registrationType, 
	fullyRegistered,
	kycCheckedStatus, 
	ageVerification, 
	pendingClosure      
	FROM gaming_clients  
	STRAIGHT_JOIN gaming_client_stats ON gaming_clients.client_id = gaming_client_stats.client_id AND gaming_client_stats.is_active=1 
	STRAIGHT_JOIN gaming_client_registrations ON gaming_client_registrations.client_id = gaming_clients.client_id AND is_current=1
	STRAIGHT_JOIN gaming_client_registration_types ON gaming_client_registration_types.client_registration_type_id = gaming_client_registrations.client_registration_type_id 
	LEFT JOIN gaming_kyc_checked_statuses ON gaming_clients.kyc_checked_status_id = gaming_kyc_checked_statuses.kyc_checked_status_id  
	LEFT JOIN gaming_client_age_verification_types AS age_verification_types ON age_verification_types.client_age_verification_type_id=gaming_clients.age_verification_type_id
	WHERE (gaming_clients.client_id = clientID AND gaming_client_registrations.is_current = 1);

	/* Region get [allow_login, allow_transfers, pin_state] */
	SET loginAllowed = 0;
	SET transferAllowed = 0;


	SELECT (SUM(x.allow_login=0)= 0) AS allow_login, (SUM(x.allow_transfers=0) = 0) as allow_transfers INTO loginAllowed, transferAllowed
	FROM (SELECT status_type, status_description, allow_login, allow_play, allow_transfers, allow_deposits
	  FROM (
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
	  )  
	) AS x;

	SET @userHasPin = 0;
	SET @indefiniteLock = 0;
	SET @tempLock = 0;

	SELECT IF(authentication_pin is null ,0,1) AS user_has_pin INTO @userHasPin
	FROM gaming_clients gc
	WHERE client_id = clientID;

	SELECT NOT(SUM((is_indefinitely=1)) = 0) AS indefinite_lock, NOT(SUM((is_indefinitely=0)) = 0) AS temp_lock INTO @indefiniteLock, @tempLock
	FROM gaming_player_restrictions gpr FORCE INDEX (client_active_non_expired)
	LEFT JOIN gaming_clients gc ON gpr.client_id=gc.client_id AND gc.authentication_pin IS NOT NULL
	WHERE gpr.client_id = clientID AND gpr.is_active=1 AND gpr.player_restriction_type_id=5 AND gpr.restrict_until_date > NOW();

	SET pinEnabled = IF (@userHasPin, 1, 0);
	SET pinEnabled = IF (NOT @indefiniteLock, 1, 0);
	SET pinEnabled = IF (NOT @tempLock, 1, 0);

	CALL PlayerSetPlayerStatus(
			accountActivated, 
			isPlayAllowed, 
			isKYCChecked, 
			depositAllowed, 
			testPlayerAllowTransfers,
			isTestPlayer,
			bonusSeeker,
			bonusDontWant,
			isSuspicious,
			withdrawalAllowed,
			riskScore,
			registrationType,
			accountClosed,
			ageVerification,
			fullyRegistered,
			kycCheckedStatus,
			pendingClosure,
			pinEnabled,
			transferAllowed,
			loginAllowed,
			clientID);

END root$$

DELIMITER ;

