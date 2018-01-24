DROP procedure IF EXISTS `FraudEventRun`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `FraudEventRun`(operatorID BIGINT, clientID BIGINT, fraudEventType VARCHAR(20), extraID BIGINT, sessionID BIGINT, balanceAccountID BIGINT, depositAmount DECIMAL(18, 5), isMinimal TINYINT(1), OUT statusCode INT)
root: BEGIN
  
  -- Ordering by client_login_attempt_id
  
  DECLARE fraudClientEventID, fraudClassificationTypeIDPrev, fraudClassificationTypeIDNew BIGINT;
  DECLARE fraudSimilarName, fraudSimilarDetails, fraudSimilarAddress VARCHAR(512) DEFAULT NULL;
  DECLARE fraudDob DATE DEFAULT NULL;
  DECLARE fraudMatchDetailsAsync, notificationEnabled TINYINT(1) DEFAULT 0;
  DECLARE LoginIPLastNum, LoginAttemptsNumForFailedRule INT DEFAULT 0;
  SET statusCode=-1;
 
  
  SET @operator_id= operatorID;
  SET @client_id = clientID;
  SET @extra_id = extraID;
  SET @session_id = sessionID;
  SET @fraud_event_type = fraudEventType;
  
  SET @balance_account_id=IF (balanceAccountID IS NULL OR balanceAccountID=0, NULL, balanceAccountID);
  SET @deposit_amount=depositAmount;
  
  
  SET @fraud_event_type_id = -1;
  SELECT fraud_event_type_id INTO @fraud_event_type_id
  FROM gaming_fraud_event_types
  WHERE name=fraudEventType;
  
  IF (@fraud_event_type_id=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  
  SET @client_stat_id=-1;
  SET @clientIDCheck=-1;
  SET @isAccountClosed=0;
 
  SELECT gaming_client_stats.client_stat_id, gaming_clients.client_id, is_account_closed 
  INTO @client_stat_id, @clientIDCheck, @isAccountClosed
  FROM gaming_clients
  JOIN gaming_client_stats ON 
    gaming_clients.client_id=@client_id AND
    gaming_clients.client_id=gaming_client_stats.client_id AND
    gaming_client_stats.is_active=1;
  
  IF (@client_stat_id=-1 OR @clientIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

  
  SET @is_manual = (SELECT @fraud_event_type='ManualRun');
  SET @is_registration = (SELECT @fraud_event_type='Registration');
  SET @is_update_details = (SELECT @fraud_event_type='UpdateDetails');
  SET @is_login = (SELECT @fraud_event_type='Login');
  SET @is_deposit = (SELECT @fraud_event_type='Deposit');
  SET @is_change_currency = (SELECT @fraud_event_type='ChangeCurrency');
  SET @is_custom = @fraud_event_type='ExternalViolation';

  
  IF (@is_manual=1 OR @is_custom=1) THEN
    SET @is_registration = 1;
    SET @is_update_details = 1;
    SET @is_login = 1;
    SET @is_deposit = 1;
    SET @is_change_currency = 1;
	SET @is_custom = 1;
  END IF;  
  
  
  SET @tmpCounter = -1;
  SELECT COUNT(*), fraud_client_event_id INTO @tmpCounter, fraudClientEventID FROM gaming_fraud_client_events WHERE client_id = @client_id AND is_current=1 LIMIT 1;
    
  IF (@tmpCounter = 0) THEN
      
	  
      INSERT INTO gaming_fraud_client_events (client_id, client_stat_id, fraud_event_type_id, extra_id, session_id, event_date, is_current)
      SELECT client_id, client_stat_id, fraud_event_type_id, @extra_id, @session_id, DATE_SUB(NOW(), INTERVAL 1 SECOND), 1
      FROM gaming_client_stats 
      JOIN gaming_fraud_event_types ON 
        gaming_client_stats.client_id=@client_id AND gaming_client_stats.is_active=1 AND
        gaming_fraud_event_types.name=@fraud_event_type;
      SET @start_event_id=LAST_INSERT_ID();
      SET fraudClientEventID=LAST_INSERT_ID();
      
	  	
	  
	  
      UPDATE gaming_fraud_client_events AS client_event
      JOIN
      (
        SELECT IFNULL(SUM(rule_points),0) AS rule_points, IFNULL(SUM(IFNULL(override_points,rule_points)),0) AS override_points
        FROM gaming_fraud_client_events_rules
        WHERE gaming_fraud_client_events_rules.fraud_client_event_id=@start_event_id
      ) AS total_points ON 1=1
      JOIN gaming_fraud_classification_types AS cls_types ON cls_types.is_active=1 AND
        IFNULL(total_points.override_points,0) >= cls_types.points_min_range AND IFNULL(total_points.override_points,0) < IFNULL(cls_types.points_max_range,2147483647)
      SET 
        client_event.rule_points=IFNULL(total_points.rule_points,0), 
        client_event.override_points=IFNULL(total_points.override_points,0), 
        client_event.fraud_classification_type_id=cls_types.fraud_classification_type_id,
        client_event.is_current=1
      WHERE client_event.fraud_client_event_id=@start_event_id; 
      
  END IF;
  
  
  
  INSERT INTO gaming_fraud_client_events(client_id, client_stat_id, fraud_event_type_id, extra_id, session_id, event_date)
  SELECT client_id, client_stat_id, fraud_event_type_id, @extra_id, @session_id, NOW()
  FROM gaming_client_stats 
  JOIN gaming_fraud_event_types ON 
    gaming_client_stats.client_id=@client_id AND gaming_client_stats.is_active=1 AND
    gaming_fraud_event_types.name=@fraud_event_type;
  
  
  SET @fraud_client_event_id=LAST_INSERT_ID();
    
  
  INSERT INTO gaming_fraud_client_events_temp(client_id, client_stat_id, fraud_event_type_id, extra_id, session_id, event_date, fraud_client_event_id)
  SELECT client_id, client_stat_id, fraud_event_type_id, @extra_id, @session_id, NOW(), @fraud_client_event_id
  FROM gaming_client_stats 
  JOIN gaming_fraud_event_types ON 
    gaming_client_stats.client_id=@client_id AND gaming_client_stats.is_active=1 AND
    gaming_fraud_event_types.name=@fraud_event_type;
    
  
  SET @fraud_client_event_temp_id=LAST_INSERT_ID(); 
    
  
  
  
  IF (@is_registration OR @is_update_details) THEN
  
	
    SET @rowCount=0;
    INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
    
    FROM gaming_clients
    JOIN clients_locations ON 
      (@client_id=0 OR gaming_clients.client_id=@client_id) AND
      gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary=1 AND
      gaming_clients.is_kyc_checked = 0
    JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id
    JOIN gaming_countries AS ip_country ON gaming_clients.country_id_from_ip=ip_country.country_id
    JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id 
    LEFT JOIN gaming_fraud_countries_languages ON 
      gaming_clients.country_id_from_ip=gaming_fraud_countries_languages.country_id AND
      clients_locations.country_id=gaming_fraud_countries_languages.country_id AND
      gaming_fraud_countries_languages.language_id=gaming_clients.language_id
    JOIN gaming_fraud_rules ON
      gaming_fraud_rules.name='ip_language_country' AND gaming_fraud_rules.is_active
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id 
    WHERE gaming_fraud_countries_languages.country_id IS NULL  
    ORDER BY gaming_clients.client_id;

    SET @calcSimilarities=IF(@is_manual=0,1,0);
    SET @calcSimilarities=1; 
 
 /*
    SELECT gaming_clients.fraud_similar_name, gaming_clients.fraud_similar_details, DATE(gaming_clients.dob), clients_locations.fraud_similar_address
    INTO fraudSimilarName, fraudSimilarDetails, fraudDob, fraudSimilarAddress
    FROM gaming_clients
    JOIN clients_locations ON 
      gaming_clients.client_id=@client_id AND
      gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary=1;
*/
   
	SELECT value_bool INTO fraudMatchDetailsAsync FROM gaming_settings WHERE NAME='FRAUD_SIMILARITY_CALC_REGISTRATION_ASYNC' LIMIT 1;
	
    IF (fraudMatchDetailsAsync AND isMinimal) THEN
		
		INSERT INTO gaming_fraud_registration_pending(client_id, event_type, extra_id, session_id, process_date)
		VALUES(@client_id, fraudEventType, extraID, sessionID, Date_Add(NOW(),INTERVAL 10 SECOND));
        
		INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points, is_original_event)
	    SELECT @fraud_client_event_temp_id, gfcer.fraud_rule_id, segment_points.points, client_overrides.points, 0
		FROM gaming_fraud_rules AS gfr 
		JOIN gaming_fraud_client_events_rules AS gfcer ON gfcer.fraud_client_event_id=fraudClientEventID AND gfr.fraud_rule_id=gfcer.fraud_rule_id AND gfr.is_active
		JOIN gaming_clients ON gaming_clients.client_id=@client_id AND gaming_clients.is_kyc_checked=0
		JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
			gfr.fraud_rule_id=segment_points.fraud_rule_id AND
			gaming_clients.client_segment_id=segment_points.client_segment_id
		LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
			gfr.fraud_rule_id=client_overrides.fraud_rule_id AND
			gaming_clients.client_id=client_overrides.client_id
		WHERE gfr.name IN ('similar_name','similar_email','similar_address');
        
	ELSE
		
	    SET @nameCount=0; SET @detailsCount=0; SET @addressCount=0;
		 
		IF (@calcSimilarities AND @is_manual=0) THEN 
		  CALL FraudMatchClientName(@client_id, @nameCount);
		  CALL FraudMatchClientDetails(@client_id, @detailsCount);
		  CALL FraudMatchClientAddress(@client_id, @addressCount);
		  COMMIT AND CHAIN;
		ELSE
		  SELECT COUNT(*) INTO @nameCount FROM gaming_fraud_similarity_thresholds AS gfst JOIN gaming_fraud_rules AS gfr ON gfst.client_id_1=@client_id AND gfr.name='similar_name' AND gfst.fraud_rule_id=gfr.fraud_rule_id;
		  SELECT COUNT(*) INTO @detailsCount FROM gaming_fraud_similarity_thresholds AS gfst JOIN gaming_fraud_rules AS gfr ON gfst.client_id_1=@client_id AND gfr.name='similar_email' AND gfst.fraud_rule_id=gfr.fraud_rule_id;
		  SELECT COUNT(*) INTO @addressCount FROM gaming_fraud_similarity_thresholds AS gfst JOIN gaming_fraud_rules AS gfr ON gfst.client_id_1=@client_id AND gfr.name='similar_address' AND gfst.fraud_rule_id=gfr.fraud_rule_id;
	    END IF;
	  
		IF (@nameCount>0) THEN
		  INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
		  SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
		  FROM gaming_fraud_rules 
		  JOIN gaming_clients ON gaming_fraud_rules.name='similar_name' AND gaming_fraud_rules.is_active AND 
			gaming_clients.client_id=@client_id AND gaming_clients.is_kyc_checked=0
		  JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
			gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
			gaming_clients.client_segment_id=segment_points.client_segment_id
		  LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
			gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
			gaming_clients.client_id=client_overrides.client_id;
		END IF;
		
		
		
		IF (@detailsCount>0) THEN
		  INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
		  SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
		  FROM gaming_fraud_rules 
		  JOIN gaming_clients ON gaming_fraud_rules.name='similar_email' AND gaming_fraud_rules.is_active AND 
			gaming_clients.client_id=@client_id AND gaming_clients.is_kyc_checked=0
		  JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
			gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
			gaming_clients.client_segment_id=segment_points.client_segment_id
		  LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
			gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
			gaming_clients.client_id=client_overrides.client_id;  
		END IF;
		
		IF (@addressCount>0) THEN
		  INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
		  SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
		  FROM gaming_fraud_rules 
		  JOIN gaming_clients ON gaming_fraud_rules.name='similar_address' AND gaming_fraud_rules.is_active AND 
			gaming_clients.client_id=@client_id AND gaming_clients.is_kyc_checked=0
		  JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
			gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
			gaming_clients.client_segment_id=segment_points.client_segment_id
		  LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
			gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
			gaming_clients.client_id=client_overrides.client_id;  
		END IF;

	END IF;
  
    
    SELECT gaming_clients.name, gaming_clients.surname INTO @client_name, @client_surname FROM gaming_clients WHERE gaming_clients.client_id=@client_id;
    SELECT FraudCheckIsFakeName(@client_name) INTO @fake_name_fired;
                
    IF (@fake_name_fired = 0) THEN
      SELECT FraudCheckIsFakeName(@client_surname) INTO @fake_name_fired;
    END IF;
    
    IF (@fake_name_fired = 1) THEN
      INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
      SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
      FROM gaming_fraud_rules 
      JOIN gaming_clients ON gaming_fraud_rules.name='fake_name' AND gaming_fraud_rules.is_active AND gaming_clients.client_id=@client_id
      JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
        gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
        gaming_clients.client_segment_id=segment_points.client_segment_id
      LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
        gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
        gaming_clients.client_id=client_overrides.client_id
      ORDER BY gaming_clients.client_id
      LIMIT 1;
    END IF;
  END IF;
  
  
  IF (@is_registration) THEN
  
    
    SET @rowCount=0;
    INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
    FROM gaming_fraud_rules
    JOIN gaming_clients ON gaming_fraud_rules.name='same_ip_address' AND gaming_fraud_rules.is_active AND
      gaming_clients.client_id=@client_id  AND gaming_clients.is_kyc_checked = 0
    JOIN gaming_clients AS gaming_clients_all ON gaming_clients_all.client_id!=@client_id AND gaming_clients_all.is_account_closed=0 AND gaming_clients_all.is_test_player=0      
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id 
    WHERE
      gaming_clients.registration_ipaddress_v4=gaming_clients_all.registration_ipaddress_v4
    ORDER BY gaming_clients.client_id
    LIMIT 1;
    
  END IF;
  
  
  IF (@is_login) THEN
  
    
    SET @rowCount=0;
    INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
    FROM gaming_fraud_rules
    JOIN gaming_clients ON gaming_fraud_rules.is_active AND gaming_clients.client_id=@client_id 
    JOIN gaming_clients_login_attempts_totals ON gaming_clients.client_id=gaming_clients_login_attempts_totals.client_id
    JOIN gaming_clients AS gaming_clients_all ON gaming_clients_all.client_id!=@client_id AND gaming_clients_all.is_account_closed=0      
    JOIN gaming_clients_login_attempts_totals AS gaming_clients_login_attempts_totals_all ON gaming_clients_all.client_id=gaming_clients_login_attempts_totals_all.client_id
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id 
    WHERE gaming_fraud_rules.name='same_ip_address_last_login' AND gaming_fraud_rules.is_active AND 
      gaming_clients_login_attempts_totals.last_ip_v4=gaming_clients_login_attempts_totals_all.last_ip_v4
    ORDER BY gaming_clients.client_id
    LIMIT 1;
    
    
    SET @rowCount=0;
    SET LoginIPLastNum = (SELECT login_ip_last_num FROM gaming_fraud_rules WHERE gaming_fraud_rules.name='login_ip_address_different_countries');  
    SET @login_ip_countries_max = (SELECT login_ip_countries_max FROM gaming_fraud_rules WHERE gaming_fraud_rules.name='login_ip_address_different_countries');
    
    INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
    FROM gaming_clients
    JOIN gaming_fraud_rules ON 
      gaming_clients.client_id=@client_id AND
      gaming_fraud_rules.name='login_ip_address_different_countries' AND gaming_fraud_rules.is_active
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id
    JOIN
    (
      SELECT COUNT(DISTINCT country_id_from_ip) AS num_different
      FROM
      (
        SELECT country_id_from_ip
        FROM gaming_clients_login_attempts WHERE client_id=@client_id 
        ORDER BY client_login_attempt_id DESC LIMIT LoginIPLastNum
      ) AS SessionLogins 
    ) AS XX ON 1=1
    WHERE XX.num_different>@login_ip_countries_max;
    
    
	SET @rowCount=0;
    SET LoginAttemptsNumForFailedRule = (SELECT login_attempts_num FROM gaming_fraud_rules WHERE gaming_fraud_rules.name='login_attempts_failed');  

    INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
    FROM gaming_clients 
    JOIN gaming_fraud_rules ON
      gaming_clients.client_id=@client_id AND
      gaming_fraud_rules.name='login_attempts_failed' AND gaming_fraud_rules.is_active
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id 
    JOIN
    ( 
      SELECT is_success 
      FROM gaming_clients_login_attempts 
      WHERE gaming_clients_login_attempts.client_id=@client_id 
      ORDER BY client_login_attempt_id DESC LIMIT LoginAttemptsNumForFailedRule
    ) AS LoginAttempts ON 1=1
    GROUP BY gaming_clients.client_id
    HAVING SUM(LoginAttempts.is_success=0) >= LoginAttemptsNumForFailedRule;
	
	
	
  END IF;
    
  
  IF (@is_registration OR @is_deposit) THEN  
    
    
  
    INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
    FROM gaming_clients
    JOIN gaming_fraud_rules ON
      gaming_fraud_rules.name='new_registered_customer' AND gaming_fraud_rules.is_active AND gaming_clients.client_id=@client_id AND gaming_clients.first_deposit_date IS NULL
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id 
    ORDER BY gaming_clients.client_id;
    
  END IF;  
  
  
  IF (@is_registration OR @is_login) THEN
    
    
    INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
    FROM gaming_clients
    LEFT JOIN gaming_clients_login_attempts_totals AS login_totals ON gaming_clients.client_id=login_totals.client_id
    JOIN gaming_fraud_ips ON 
      gaming_fraud_ips.is_active=1 AND
      (gaming_clients.registration_ipaddress_v4 LIKE CONCAT(gaming_fraud_ips.ip_v4_address,'%') OR
      (login_totals.last_ip_v4 IS NOT NULL AND login_totals.last_ip_v4 LIKE CONCAT(gaming_fraud_ips.ip_v4_address,'%')))
    JOIN gaming_fraud_ips_status_types ON
      gaming_fraud_ips_status_types.name='BlackListed' AND
      gaming_fraud_ips.fraud_ip_status_type_id=gaming_fraud_ips_status_types.fraud_ip_status_type_id  
    JOIN gaming_fraud_rules ON
      gaming_fraud_rules.name='blacklisted_ips' AND gaming_fraud_rules.is_active
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id 
    WHERE gaming_clients.client_id=@client_id
    ORDER BY gaming_clients.client_id
	LIMIT 1;
    
    
    INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
    FROM gaming_clients
    LEFT JOIN gaming_clients_login_attempts_totals AS login_totals ON gaming_clients.client_id=login_totals.client_id
    JOIN gaming_fraud_ips ON 
      gaming_fraud_ips.is_active=1 AND
      (gaming_clients.registration_ipaddress_v4 LIKE CONCAT(gaming_fraud_ips.ip_v4_address,'%') OR
      (login_totals.last_ip_v4 IS NOT NULL AND login_totals.last_ip_v4 LIKE CONCAT(gaming_fraud_ips.ip_v4_address,'%')))
    JOIN gaming_fraud_ips_status_types ON
      gaming_fraud_ips_status_types.name='WatchListed' AND
      gaming_fraud_ips.fraud_ip_status_type_id=gaming_fraud_ips_status_types.fraud_ip_status_type_id  
    JOIN gaming_fraud_rules ON
      gaming_fraud_rules.name='watchlisted_ips' AND gaming_fraud_rules.is_active
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id 
    WHERE gaming_clients.client_id=@client_id 
    ORDER BY gaming_clients.client_id
    LIMIT 1;
     

  END IF;
  
  IF (@is_deposit) THEN
  
    
    INSERT INTO gaming_fraud_client_events_rules_temp (fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, LEAST(max_trigger_num, COUNT(gaming_clients.client_id)) * segment_points.points, LEAST(max_trigger_num, COUNT(gaming_clients.client_id)) * client_overrides.points
    
    FROM gaming_clients
    JOIN gaming_client_stats ON 
      (@client_id=0 OR gaming_clients.client_id=@client_id) AND
      gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
    JOIN gaming_balance_accounts ON
      gaming_client_stats.client_stat_id=gaming_balance_accounts.client_stat_id AND gaming_balance_accounts.fraud_checkable=1 AND gaming_balance_accounts.is_active = 1
    JOIN gaming_payment_method ON
      gaming_payment_method.name='CreditCard' AND
      gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id
    JOIN gaming_fraud_iins ON 
      gaming_fraud_iins.is_active=1 AND 
      SUBSTRING(gaming_balance_accounts.account_reference,1,6)=gaming_fraud_iins.iin_code AND gaming_fraud_iins.is_banned=1 
    JOIN gaming_fraud_rules ON
      gaming_fraud_rules.name='blacklisted_iins' AND gaming_fraud_rules.is_active
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id 
    GROUP BY gaming_clients.client_id  
    ORDER BY gaming_clients.client_id;
    
	
    INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, LEAST(max_trigger_num, COUNT(gaming_clients.client_id)) * segment_points.points, LEAST(max_trigger_num, COUNT(gaming_clients.client_id)) * client_overrides.points
    
    FROM gaming_clients
    JOIN gaming_client_stats ON 
      (@client_id=0 OR gaming_clients.client_id=@client_id) AND
      gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
    JOIN gaming_balance_accounts ON
      gaming_client_stats.client_stat_id=gaming_balance_accounts.client_stat_id AND gaming_balance_accounts.fraud_checkable=1
    JOIN gaming_payment_method ON
      gaming_payment_method.name='CreditCard' AND
      gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id AND
      gaming_balance_accounts.account_reference NOT IN ('InvalidAccount')
    JOIN gaming_fraud_rules ON
      gaming_fraud_rules.name='different_cc_holder_name' AND gaming_fraud_rules.is_active
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id 
    WHERE gaming_balance_accounts.cc_holder_name IS NOT NULL AND UPPER(REPLACE(CONCAT_WS('',gaming_balance_accounts.cc_holder_name),' ',''))!=UPPER(REPLACE(CONCAT_WS('',gaming_clients.name,surname),' ','')) 
    GROUP BY gaming_clients.client_id 
    ORDER BY gaming_clients.client_id; 
    
	
    INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, LEAST(max_trigger_num, COUNT(gaming_clients.client_id)) * segment_points.points, LEAST(max_trigger_num, COUNT(gaming_clients.client_id)) * client_overrides.points
    
    
    FROM gaming_clients
    JOIN gaming_client_stats ON 
      (@client_id=0 OR gaming_clients.client_id=@client_id) AND
      gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
    JOIN gaming_balance_accounts ON
      gaming_client_stats.client_stat_id=gaming_balance_accounts.client_stat_id AND gaming_balance_accounts.fraud_checkable=1
    JOIN gaming_payment_method ON
      gaming_payment_method.name='CreditCard' AND
      gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id AND
      gaming_balance_accounts.account_reference NOT IN ('InvalidAccount')
    JOIN gaming_fraud_iins ON 
      gaming_fraud_iins.is_active=1 AND 
      SUBSTRING(gaming_balance_accounts.account_reference,1,6)=gaming_fraud_iins.iin_code AND
      gaming_clients.country_id_from_ip!=gaming_fraud_iins.country_id 
    JOIN gaming_countries ON
      gaming_fraud_iins.country_id=gaming_countries.country_id
    JOIN gaming_countries AS country_ip ON
      gaming_clients.country_id_from_ip=country_ip.country_id
    JOIN gaming_fraud_rules ON
      gaming_fraud_rules.name='iin_ip_country' AND gaming_fraud_rules.is_active
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id 
    GROUP BY gaming_clients.client_id
    ORDER BY gaming_clients.client_id; 

	


    IF (@balance_account_id IS NOT NULL) THEN 
      
	  
      
      INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)  
      SELECT @fraud_client_event_id, NewViolation.fraud_rule_id, NewViolation.client_id, 1, NewViolation.rule_points, NewViolation.override_points, NewViolation.date_created
      FROM
      (
        SELECT 
          gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, gaming_fraud_rules.cc_registered_period, gaming_fraud_rules.cc_registered_num, 
          segment_points.points AS rule_points, client_overrides.points AS override_points, NOW() AS date_created
        
        FROM gaming_clients
        JOIN gaming_client_stats ON 
          (@client_id=0 OR gaming_clients.client_id=@client_id) AND
          gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
        JOIN gaming_fraud_rules ON
          gaming_fraud_rules.name='aggregated_credit_cards' AND gaming_fraud_rules.is_active
        JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
          gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
          gaming_clients.client_segment_id=segment_points.client_segment_id
        LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
          gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
          gaming_clients.client_id=client_overrides.client_id 
        JOIN gaming_balance_accounts ON
          gaming_client_stats.client_stat_id=gaming_balance_accounts.client_stat_id AND gaming_balance_accounts.fraud_checkable=1 AND
          gaming_balance_accounts.date_created > DATE_SUB(NOW(), INTERVAL gaming_fraud_rules.cc_registered_period MINUTE) AND
          gaming_balance_accounts.account_reference NOT IN ('InvalidAccount','Account') 
        JOIN gaming_payment_method ON
          gaming_payment_method.name='CreditCard' AND 
          gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id
        GROUP BY gaming_clients.client_id 
        HAVING COUNT(gaming_clients.client_id) >= cc_registered_num 
      ) AS NewViolation
      LEFT JOIN gaming_fraud_client_events_violations AS violations ON 
        NewViolation.fraud_rule_id=violations.fraud_rule_id AND
        NewViolation.client_id=violations.client_id AND
        violations.cascade_points=1 AND DATE_ADD(violations.date_created, INTERVAL cc_registered_period MINUTE)>NewViolation.date_created
      WHERE violations.fraud_client_event_violation_id IS NULL;
      
      
      INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)  
      SELECT @fraud_client_event_id, NewViolation.fraud_rule_id, NewViolation.client_id, 1, NewViolation.rule_points, NewViolation.override_points, NewViolation.date_created
      FROM
      (
        SELECT fraud_rule_id, client_id, cc_registered_period, cc_registered_num, rule_points, override_points, date_created
        FROM 
        (
          SELECT 
            gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, gaming_fraud_rules.cc_registered_period, gaming_fraud_rules.cc_registered_num, gaming_payment_method.payment_method_id,
            segment_points.points AS rule_points, client_overrides.points AS override_points, NOW() AS date_created
          
          FROM gaming_clients
          JOIN gaming_client_stats ON 
            (@client_id=0 OR gaming_clients.client_id=@client_id) AND
            gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
          JOIN gaming_fraud_rules ON
            gaming_fraud_rules.name='aggregated_payment_methods' AND gaming_fraud_rules.is_active
          JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
            gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
            gaming_clients.client_segment_id=segment_points.client_segment_id
          LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
            gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
            gaming_clients.client_id=client_overrides.client_id 
          JOIN gaming_balance_accounts ON
            gaming_client_stats.client_stat_id=gaming_balance_accounts.client_stat_id AND gaming_balance_accounts.fraud_checkable=1 AND
            gaming_balance_accounts.date_created > DATE_SUB(NOW(), INTERVAL gaming_fraud_rules.cc_registered_period MINUTE)
          JOIN gaming_payment_method ON
            gaming_payment_method.name<>'CreditCard' AND 
            gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id
          GROUP BY gaming_clients.client_id, payment_method_id 
          HAVING COUNT(*) >= cc_registered_num 
        ) AS XX
        GROUP BY client_id
      ) AS NewViolation
      LEFT JOIN gaming_fraud_client_events_violations AS violations ON 
        NewViolation.fraud_rule_id=violations.fraud_rule_id AND
        NewViolation.client_id=violations.client_id AND
        violations.cascade_points=1 AND DATE_ADD(violations.date_created, INTERVAL cc_registered_period MINUTE)>NewViolation.date_created
      WHERE violations.fraud_client_event_violation_id IS NULL;
      
      
      INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)  
          SELECT @fraud_client_event_id, NewViolation.fraud_rule_id, NewViolation.client_id, 1, NewViolation.rule_points, NewViolation.override_points, NewViolation.date_created
      FROM
      (
        SELECT 
          gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, gaming_fraud_rules.frequent_deposits_period, gaming_fraud_rules.frequent_num_deposits,
          segment_points.points AS rule_points, client_overrides.points AS override_points, NOW() AS date_created
        
        FROM gaming_clients
        JOIN gaming_client_stats ON 
          (@client_id=0 OR gaming_clients.client_id=@client_id) AND
          gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
        JOIN gaming_fraud_rules ON
          gaming_fraud_rules.name='frequent_deposits' AND gaming_fraud_rules.is_active
        JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
          gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
          gaming_clients.client_segment_id=segment_points.client_segment_id
        LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
          gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
          gaming_clients.client_id=client_overrides.client_id
        JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
        JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name IN('Accepted', 'Authorized_Pending')
        JOIN gaming_balance_history ON
          gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id AND
          gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
          gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id AND       
          gaming_balance_history.timestamp >= DATE_SUB(NOW(), INTERVAL gaming_fraud_rules.frequent_deposits_period MINUTE) AND
          gaming_balance_history.amount_base <= gaming_fraud_rules.frequent_max_deposit_amount 
        JOIN gaming_payment_method ON
          
          gaming_balance_history.payment_method_id=gaming_payment_method.payment_method_id
        GROUP BY gaming_clients.client_id
        HAVING COUNT(gaming_balance_history.balance_history_id) + 1 >= frequent_num_deposits 
      ) AS NewViolation
      LEFT JOIN gaming_fraud_client_events_violations AS violations ON 
        NewViolation.fraud_rule_id=violations.fraud_rule_id AND
        NewViolation.client_id=violations.client_id AND
        violations.cascade_points=1 AND DATE_ADD(violations.date_created, INTERVAL NewViolation.frequent_deposits_period MINUTE)>NewViolation.date_created
      WHERE violations.fraud_client_event_violation_id IS NULL;

	INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)  
          SELECT @fraud_client_event_id, NewViolation.fraud_rule_id, NewViolation.client_id, 1, NewViolation.rule_points, NewViolation.override_points, NewViolation.date_created
      FROM
      (
        SELECT 
          gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, gaming_fraud_rules.frequent_deposits_period, gaming_fraud_rules.frequent_num_deposits,
          segment_points.points AS rule_points, client_overrides.points AS override_points, NOW() AS date_created
        
        FROM gaming_clients
        JOIN gaming_client_stats ON 
          (@client_id=0 OR gaming_clients.client_id=@client_id) AND
          gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
        JOIN gaming_fraud_rules ON
          gaming_fraud_rules.name='declined_deposits' AND gaming_fraud_rules.is_active
        JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
          gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
          gaming_clients.client_segment_id=segment_points.client_segment_id
        LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
          gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
          gaming_clients.client_id=client_overrides.client_id
        JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
        JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name IN('Declined', 'Rejected')
        JOIN gaming_balance_history ON
          gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id AND
          gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
          gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id AND       
          gaming_balance_history.timestamp >= DATE_SUB(NOW(), INTERVAL gaming_fraud_rules.frequent_deposits_period MINUTE) 
        JOIN gaming_payment_method ON
          
          gaming_balance_history.payment_method_id=gaming_payment_method.payment_method_id
        GROUP BY gaming_clients.client_id
        HAVING COUNT(gaming_balance_history.balance_history_id) + 1 >= frequent_num_deposits 
      ) AS NewViolation
      LEFT JOIN gaming_fraud_client_events_violations AS violations ON 
        NewViolation.fraud_rule_id=violations.fraud_rule_id AND
        NewViolation.client_id=violations.client_id AND
        violations.cascade_points=1 AND DATE_ADD(violations.date_created, INTERVAL NewViolation.frequent_deposits_period MINUTE)>NewViolation.date_created
      WHERE violations.fraud_client_event_violation_id IS NULL;


    INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)  
          SELECT @fraud_client_event_id, NewViolation.fraud_rule_id, NewViolation.client_id, 1, NewViolation.rule_points, NewViolation.override_points, NewViolation.date_created
      FROM
      (
        SELECT 
          gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, gaming_fraud_rules.frequent_deposits_period, gaming_fraud_rules.frequent_max_deposit_amount,
          segment_points.points AS rule_points, client_overrides.points AS override_points, NOW() AS date_created
        
        FROM gaming_clients
        JOIN gaming_client_stats ON 
          (@client_id=0 OR gaming_clients.client_id=@client_id) AND
          gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
        JOIN gaming_fraud_rules ON
          gaming_fraud_rules.name='deposits_after_first_deposit' AND gaming_fraud_rules.is_active
        JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
          gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
          gaming_clients.client_segment_id=segment_points.client_segment_id
        LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
          gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
          gaming_clients.client_id=client_overrides.client_id
        JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
        JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name IN('Accepted', 'Authorized_Pending')
        JOIN gaming_balance_history ON
          gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id AND
          gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
          gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id AND       
          gaming_balance_history.timestamp >= gaming_clients.first_deposit_date AND 
		  gaming_balance_history.timestamp <= DATE_ADD(gaming_clients.first_deposit_date, INTERVAL frequent_deposits_period MINUTE)
        JOIN gaming_payment_method ON gaming_balance_history.payment_method_id=gaming_payment_method.payment_method_id
        GROUP BY gaming_clients.client_id
        HAVING SUM(gaming_balance_history.amount_base) + IFNULL(@deposit_amount, 0) >= gaming_fraud_rules.frequent_max_deposit_amount
      ) AS NewViolation
      LEFT JOIN gaming_fraud_client_events_violations AS violations ON 
        NewViolation.fraud_rule_id=violations.fraud_rule_id AND
        NewViolation.client_id=violations.client_id AND
        violations.cascade_points=1 AND DATE_ADD(violations.date_created, INTERVAL NewViolation.frequent_deposits_period MINUTE)>NewViolation.date_created
      WHERE violations.fraud_client_event_violation_id IS NULL;

	INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)  
          SELECT @fraud_client_event_id, NewViolation.fraud_rule_id, NewViolation.client_id, 1, NewViolation.rule_points, NewViolation.override_points, NewViolation.date_created
      FROM
      (
        SELECT 
          gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, gaming_fraud_rules.frequent_max_deposit_amount, gaming_fraud_rules.frequent_deposits_period,
          segment_points.points AS rule_points, client_overrides.points AS override_points, NOW() AS date_created
        
        FROM gaming_clients
        JOIN gaming_client_stats ON 
          (@client_id=0 OR gaming_clients.client_id=@client_id) AND
          gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
        JOIN gaming_fraud_rules ON
          gaming_fraud_rules.name='deposit_velocity_1' AND gaming_fraud_rules.is_active
        JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
          gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
          gaming_clients.client_segment_id=segment_points.client_segment_id
        LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
          gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
          gaming_clients.client_id=client_overrides.client_id
        LEFT JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
        LEFT JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name IN('Accepted', 'Authorized_Pending')
        LEFT JOIN gaming_balance_history ON
          gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id AND
          gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
          gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id AND       
          gaming_balance_history.timestamp >= DATE_SUB(NOW(), INTERVAL gaming_fraud_rules.frequent_deposits_period MINUTE)
        LEFT JOIN gaming_payment_method ON
          gaming_balance_history.payment_method_id=gaming_payment_method.payment_method_id
        GROUP BY gaming_clients.client_id
        HAVING IFNULL(SUM(gaming_balance_history.amount_base), 0) + IFNULL(@deposit_amount, 0) >= gaming_fraud_rules.frequent_max_deposit_amount 
      ) AS NewViolation
      LEFT JOIN gaming_fraud_client_events_violations AS violations ON 
        NewViolation.fraud_rule_id=violations.fraud_rule_id AND
        NewViolation.client_id=violations.client_id AND
        violations.cascade_points=1 AND DATE_ADD(violations.date_created, INTERVAL NewViolation.frequent_deposits_period MINUTE)>NewViolation.date_created
      WHERE violations.fraud_client_event_violation_id IS NULL;

	INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)  
          SELECT @fraud_client_event_id, NewViolation.fraud_rule_id, NewViolation.client_id, 1, NewViolation.rule_points, NewViolation.override_points, NewViolation.date_created
      FROM
      (
        SELECT 
          gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, gaming_fraud_rules.frequent_max_deposit_amount, gaming_fraud_rules.frequent_deposits_period,
          segment_points.points AS rule_points, client_overrides.points AS override_points, NOW() AS date_created
        
        FROM gaming_clients
        JOIN gaming_client_stats ON 
          (@client_id=0 OR gaming_clients.client_id=@client_id) AND
          gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
        JOIN gaming_fraud_rules ON
          gaming_fraud_rules.name='deposit_velocity_2' AND gaming_fraud_rules.is_active
        JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
          gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
          gaming_clients.client_segment_id=segment_points.client_segment_id
        LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
          gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
          gaming_clients.client_id=client_overrides.client_id
        LEFT JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
        LEFT JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name IN('Accepted', 'Authorized_Pending')
        LEFT JOIN gaming_balance_history ON
          gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id AND
          gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
          gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id AND       
          gaming_balance_history.timestamp >= DATE_SUB(NOW(), INTERVAL gaming_fraud_rules.frequent_deposits_period MINUTE)
        LEFT JOIN gaming_payment_method ON
          gaming_balance_history.payment_method_id=gaming_payment_method.payment_method_id
        GROUP BY gaming_clients.client_id
        HAVING IFNULL(SUM(gaming_balance_history.amount_base), 0) + IFNULL(@deposit_amount, 0) >= gaming_fraud_rules.frequent_max_deposit_amount 
      ) AS NewViolation
      LEFT JOIN gaming_fraud_client_events_violations AS violations ON 
        NewViolation.fraud_rule_id=violations.fraud_rule_id AND
        NewViolation.client_id=violations.client_id AND
        violations.cascade_points=1 AND DATE_ADD(violations.date_created, INTERVAL NewViolation.frequent_deposits_period MINUTE)>NewViolation.date_created
      WHERE violations.fraud_client_event_violation_id IS NULL;

	INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)  
          SELECT @fraud_client_event_id, NewViolation.fraud_rule_id, NewViolation.client_id, 1, NewViolation.rule_points, NewViolation.override_points, NewViolation.date_created
      FROM
      (
        SELECT 
          gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, gaming_fraud_rules.frequent_max_deposit_amount, gaming_fraud_rules.frequent_deposits_period,
          segment_points.points AS rule_points, client_overrides.points AS override_points, NOW() AS date_created
        
        FROM gaming_clients
        JOIN gaming_client_stats ON 
          (@client_id=0 OR gaming_clients.client_id=@client_id) AND
          gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
        JOIN gaming_fraud_rules ON
          gaming_fraud_rules.name='deposit_velocity_3' AND gaming_fraud_rules.is_active
        JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
          gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
          gaming_clients.client_segment_id=segment_points.client_segment_id
        LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
          gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
          gaming_clients.client_id=client_overrides.client_id
        LEFT JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
        LEFT JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name IN('Accepted', 'Authorized_Pending')
        LEFT JOIN gaming_balance_history ON
          gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id AND
          gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
          gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id AND       
          gaming_balance_history.timestamp >= DATE_SUB(NOW(), INTERVAL gaming_fraud_rules.frequent_deposits_period MINUTE)
        LEFT JOIN gaming_payment_method ON
          gaming_balance_history.payment_method_id=gaming_payment_method.payment_method_id
        GROUP BY gaming_clients.client_id
        HAVING IFNULL(SUM(gaming_balance_history.amount_base), 0) + IFNULL(@deposit_amount, 0) >= gaming_fraud_rules.frequent_max_deposit_amount 
      ) AS NewViolation
      LEFT JOIN gaming_fraud_client_events_violations AS violations ON 
        NewViolation.fraud_rule_id=violations.fraud_rule_id AND
        NewViolation.client_id=violations.client_id AND
        violations.cascade_points=1 AND DATE_ADD(violations.date_created, INTERVAL NewViolation.frequent_deposits_period MINUTE)>NewViolation.date_created
      WHERE violations.fraud_client_event_violation_id IS NULL;

	INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)  
          SELECT @fraud_client_event_id, NewViolation.fraud_rule_id, NewViolation.client_id, 1, NewViolation.rule_points, NewViolation.override_points, NewViolation.date_created
      FROM
      (
        SELECT 
          gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, gaming_fraud_rules.frequent_deposits_period, gaming_fraud_rules.frequent_num_deposits,
          segment_points.points AS rule_points, client_overrides.points AS override_points, NOW() AS date_created
        
        FROM gaming_clients
        JOIN gaming_client_stats ON 
          (@client_id=0 OR gaming_clients.client_id=@client_id) AND
          gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
        JOIN gaming_fraud_rules ON
          gaming_fraud_rules.name='frequent_cc_deposits' AND gaming_fraud_rules.is_active
        JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
          gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
          gaming_clients.client_segment_id=segment_points.client_segment_id
        LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
          gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
          gaming_clients.client_id=client_overrides.client_id
        JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
        JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name IN('Accepted', 'Authorized_Pending')
        JOIN gaming_balance_history ON
          gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id AND
          gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
          gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id AND       
          gaming_balance_history.timestamp >= DATE_SUB(NOW(), INTERVAL gaming_fraud_rules.frequent_deposits_period MINUTE)
        JOIN gaming_payment_method ON          
          gaming_balance_history.payment_method_id=gaming_payment_method.payment_method_id AND gaming_payment_method.name = 'CreditCard'
        GROUP BY gaming_clients.client_id
        HAVING COUNT(gaming_balance_history.balance_history_id) + 1 >= gaming_fraud_rules.frequent_num_deposits 
      ) AS NewViolation
      LEFT JOIN gaming_fraud_client_events_violations AS violations ON 
        NewViolation.fraud_rule_id=violations.fraud_rule_id AND
        NewViolation.client_id=violations.client_id AND
        violations.cascade_points=1 AND DATE_ADD(violations.date_created, INTERVAL NewViolation.frequent_deposits_period MINUTE)>NewViolation.date_created
      WHERE violations.fraud_client_event_violation_id IS NULL;

	INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)  
          SELECT @fraud_client_event_id, NewViolation.fraud_rule_id, NewViolation.client_id, 1, NewViolation.rule_points, NewViolation.override_points, NewViolation.date_created
      FROM
      (
        SELECT 
          gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, gaming_fraud_rules.frequent_deposits_period, gaming_fraud_rules.frequent_num_deposits,
          segment_points.points AS rule_points, client_overrides.points AS override_points, NOW() AS date_created
        
        FROM gaming_clients
        JOIN gaming_client_stats ON 
          (@client_id=0 OR gaming_clients.client_id=@client_id) AND
          gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
        JOIN gaming_fraud_rules ON
          gaming_fraud_rules.name='frequent_alternate_deposits' AND gaming_fraud_rules.is_active
        JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
          gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
          gaming_clients.client_segment_id=segment_points.client_segment_id
        LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
          gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
          gaming_clients.client_id=client_overrides.client_id
        JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
        JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name IN('Accepted', 'Authorized_Pending')
        JOIN gaming_balance_history ON
          gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id AND
          gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND
          gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id AND       
          gaming_balance_history.timestamp >= DATE_SUB(NOW(), INTERVAL gaming_fraud_rules.frequent_deposits_period MINUTE)
        JOIN gaming_payment_method ON          
          gaming_balance_history.payment_method_id=gaming_payment_method.payment_method_id AND gaming_payment_method.name != 'CreditCard'
        GROUP BY gaming_clients.client_id
        HAVING COUNT(gaming_balance_history.balance_history_id) + 1 >= gaming_fraud_rules.frequent_num_deposits 
      ) AS NewViolation
      LEFT JOIN gaming_fraud_client_events_violations AS violations ON 
        NewViolation.fraud_rule_id=violations.fraud_rule_id AND
        NewViolation.client_id=violations.client_id AND
        violations.cascade_points=1 AND DATE_ADD(violations.date_created, INTERVAL NewViolation.frequent_deposits_period MINUTE)>NewViolation.date_created
      WHERE violations.fraud_client_event_violation_id IS NULL;


    
    END IF; 

    SELECT COUNT(balance_history_id) AS num_deposits INTO @numDeposits 
    FROM gaming_clients
    JOIN gaming_client_stats ON 
      gaming_client_stats.client_stat_id=@client_stat_id AND
      gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1 
    JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' 
    JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name IN('Accepted', 'Authorized_Pending')
    LEFT JOIN gaming_balance_history ON
      gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id AND
      gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id AND 
      gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id
    GROUP BY gaming_client_stats.client_stat_id;
  
    IF ( (@numDeposits > 0) AND (@balance_account_id IS NOT NULL) ) THEN
    
      
      SET @transactionsPerAccount=0;
      SET @daysLimit=365;
      SELECT transactions_per_account, transactions_day_limit INTO @transactionsPerAccount, @daysLimit
      FROM gaming_fraud_rules 
      WHERE gaming_fraud_rules.name='large_deposit_before_kyc';
      INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)
      SELECT @fraud_client_event_id, gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, 1, segment_points.points, client_overrides.points, NOW()
       FROM gaming_clients
      JOIN gaming_client_stats ON 
        gaming_clients.client_id=@client_id AND
        gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
      JOIN gaming_balance_accounts ON
        gaming_balance_accounts.balance_account_id=@balance_account_id AND kyc_checked=0 AND
        gaming_client_stats.client_stat_id=gaming_balance_accounts.client_stat_id 
      JOIN gaming_client_segments ON
        gaming_clients.client_id=@client_id AND
        gaming_clients.client_segment_id=gaming_client_segments.client_segment_id
      JOIN gaming_fraud_rules ON gaming_fraud_rules.name='large_deposit_before_kyc' AND gaming_fraud_rules.is_active
      JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
        gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND 
        gaming_clients.client_segment_id=segment_points.client_segment_id
      LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
        gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
        gaming_clients.client_id=client_overrides.client_id
      LEFT JOIN
      (
        SELECT gaming_clients.client_id, AVG(gaming_balance_history.amount) AS deposit_avg, IFNULL(STDDEV_SAMP(gaming_balance_history.amount), 0) AS deposit_std, gaming_balance_history.balance_account_id
        FROM gaming_clients
        JOIN gaming_client_stats ON 
          gaming_clients.client_id=@client_id AND
          gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
        JOIN gaming_balance_history ON gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id AND gaming_balance_history.timestamp>=@afterDate
        JOIN gaming_payment_transaction_type ON
          gaming_payment_transaction_type.name='Deposit' AND 
          gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
        JOIN gaming_payment_transaction_status ON
          gaming_payment_transaction_status.name IN('Accepted', 'Authorized_Pending') AND 
          gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id 
        GROUP BY IF (@transactionsPerAccount=0, gaming_clients.client_id, gaming_balance_history.balance_account_id)
      ) AS DepositSummary ON gaming_clients.client_id=DepositSummary.client_id AND (@transactionsPerAccount=0 OR gaming_balance_accounts.balance_account_id=DepositSummary.balance_account_id)
      WHERE 
        (DepositSummary.client_id IS NOT NULL) AND 
        ((large_deposit_use_advanced=0 AND @deposit_amount>DepositSummary.deposit_avg*large_deposit_multiplier) OR
        (large_deposit_use_advanced=1 AND @deposit_amount>
          DepositSummary.deposit_avg +
            ((DepositSummary.deposit_std*fraud_std_multiplier)+ 
            (DepositSummary.deposit_avg*fraud_k*fraud_mean_k_multiplier))*fraud_conf_n)
        );
      
      
      SET @transactionsPerAccount=0;
      SET @daysLimit=365;      
      SELECT transactions_per_account, transactions_day_limit INTO @transactionsPerAccount, @daysLimit
      FROM gaming_fraud_rules 
      WHERE gaming_fraud_rules.name='large_deposit_after_kyc';
        
      INSERT INTO gaming_fraud_client_events_violations
        (fraud_client_event_id, fraud_rule_id, client_id, cascade_points, rule_points, override_points, date_created)
      SELECT @fraud_client_event_id, gaming_fraud_rules.fraud_rule_id, gaming_clients.client_id, 1, segment_points.points, client_overrides.points, NOW()
       FROM gaming_clients
      JOIN gaming_client_stats ON 
        gaming_clients.client_id=@client_id AND
        gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
      JOIN gaming_balance_accounts ON
        gaming_balance_accounts.balance_account_id=@balance_account_id AND kyc_checked=1 AND
        gaming_client_stats.client_stat_id=gaming_balance_accounts.client_stat_id 
      JOIN gaming_client_segments ON
        gaming_clients.client_id=@client_id AND
        gaming_clients.client_segment_id=gaming_client_segments.client_segment_id
      JOIN gaming_fraud_rules ON gaming_fraud_rules.name='large_deposit_after_kyc' AND gaming_fraud_rules.is_active
      JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
        gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND 
        gaming_clients.client_segment_id=segment_points.client_segment_id
      LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
        gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
        gaming_clients.client_id=client_overrides.client_id
      LEFT JOIN
      (
        SELECT gaming_clients.client_id, AVG(gaming_balance_history.amount) AS deposit_avg, IFNULL(STDDEV_SAMP(gaming_balance_history.amount), 0) AS deposit_std, gaming_balance_history.balance_account_id
        FROM gaming_clients
        JOIN gaming_client_stats ON 
          gaming_clients.client_id=@client_id AND
          gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active
        JOIN gaming_balance_history ON gaming_client_stats.client_stat_id=gaming_balance_history.client_stat_id AND gaming_balance_history.timestamp>=@afterDate
        JOIN gaming_payment_transaction_type ON
          gaming_payment_transaction_type.name='Deposit' AND 
          gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
        JOIN gaming_payment_transaction_status ON
          gaming_payment_transaction_status.name IN('Accepted', 'Authorized_Pending') AND 
          gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id 
        GROUP BY IF (@transactionsPerAccount=0, gaming_clients.client_id, gaming_balance_history.balance_account_id)
      ) AS DepositSummary ON gaming_clients.client_id=DepositSummary.client_id AND (@transactionsPerAccount=0 OR gaming_balance_accounts.balance_account_id=DepositSummary.balance_account_id)
      WHERE 
        (DepositSummary.client_id IS NOT NULL) AND 
        ((large_deposit_use_advanced=0 AND @deposit_amount>DepositSummary.deposit_avg*large_deposit_multiplier) OR
        (large_deposit_use_advanced=1 AND @deposit_amount>
          DepositSummary.deposit_avg +
            ((DepositSummary.deposit_std*fraud_std_multiplier)+ 
            (DepositSummary.deposit_avg*fraud_k*fraud_mean_k_multiplier))*fraud_conf_n)
        );  
      
    END IF; 
    
    
    
    
    
    INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)  
    SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
    FROM gaming_fraud_rules 
    JOIN gaming_clients ON 
      gaming_clients.client_id=@client_id 
    JOIN gaming_client_stats ON
      gaming_clients.client_id = gaming_client_stats.client_id  AND
      gaming_client_stats.is_active=1 
    JOIN gaming_payment_method ON gaming_payment_method.name='CreditCard' AND gaming_payment_method.is_sub_method=0 
    JOIN gaming_balance_accounts ON
      gaming_balance_accounts.is_active=1 AND
      gaming_balance_accounts.client_stat_id=gaming_client_stats.client_stat_id AND gaming_balance_accounts.fraud_checkable=1 AND
      gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id AND
      gaming_balance_accounts.account_reference NOT IN ('InvalidAccount','Account') 
    JOIN gaming_clients AS gaming_clients_all ON
      gaming_clients_all.client_id!=@client_id AND
      gaming_clients_all.is_account_closed=0
    JOIN gaming_client_stats AS gaming_client_stats_all ON 
      gaming_clients_all.client_id = gaming_client_stats_all.client_id  AND 
      gaming_client_stats_all.is_active=1 
    JOIN gaming_balance_accounts AS gaming_balance_accounts_all ON
      gaming_balance_accounts_all.is_active=1 AND
      gaming_balance_accounts_all.client_stat_id=gaming_client_stats_all.client_stat_id AND
      gaming_balance_accounts_all.payment_method_id=gaming_payment_method.payment_method_id AND
      gaming_balance_accounts.account_reference=gaming_balance_accounts_all.account_reference
    JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
      gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
      gaming_clients.client_segment_id=segment_points.client_segment_id
    LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
      gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
      gaming_clients.client_id=client_overrides.client_id 
    WHERE gaming_fraud_rules.name='same_credit_card_account_ref' AND gaming_fraud_rules.is_active
    LIMIT 1;
    
    
    
    
    
    SET @beforeKYCDepositLimitEnabled = 0;    
    SET @currencyIDCheck = -1; 
    SET @beforeKYCDepositLimit = 0; 
          
    SELECT value_bool INTO @beforeKYCDepositLimitEnabled FROM gaming_settings WHERE NAME='TRANSFER_BEFORE_KYC_DEPOSIT_LIMIT_ENABLED' LIMIT 1;
      
    IF (@beforeKYCDepositLimitEnabled=1) THEN
        SELECT gaming_payment_amounts.currency_id, before_kyc_deposit_limit
        INTO @currencyIDCheck, @beforeKYCDepositLimit
        FROM gaming_clients
        JOIN gaming_client_stats ON gaming_clients.client_id=@client_id  AND gaming_clients.client_id = gaming_client_stats.client_id AND gaming_client_stats.is_active=1
        JOIN gaming_payment_amounts ON gaming_client_stats.currency_id=gaming_payment_amounts.currency_id
        LIMIT 1;
        
        IF (@currencyIDCheck=-1) THEN
          SET statusCode=1;
          LEAVE root;
        END IF;
        
        INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points)
        SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, segment_points.points, client_overrides.points
        FROM gaming_clients
        JOIN gaming_client_stats ON 
              gaming_client_stats.client_id=gaming_clients.client_id AND 
              gaming_client_stats.is_active=1 AND 
              gaming_clients.client_id=@client_id AND 
              gaming_clients.is_kyc_checked = 0
        JOIN gaming_fraud_rules ON 
            gaming_fraud_rules.name='customer_reaching_pre_kyc_limits' AND gaming_fraud_rules.is_active AND 
            ((deposited_amount+IFNULL(@deposit_amount,0))/@beforeKYCDepositLimit) >= gaming_fraud_rules.kyc_remaining_percentage
        JOIN gaming_fraud_rules_client_segments_points AS segment_points ON
            gaming_fraud_rules.fraud_rule_id=segment_points.fraud_rule_id AND
            gaming_clients.client_segment_id=segment_points.client_segment_id
        LEFT JOIN gaming_fraud_rules_client_overrides AS client_overrides ON
            gaming_fraud_rules.fraud_rule_id=client_overrides.fraud_rule_id AND
            gaming_clients.client_id=client_overrides.client_id;
            
    END IF; 
  END IF; 

  
  UPDATE gaming_fraud_client_events_rules_temp AS rules_temp
  LEFT JOIN (
	SELECT fraud_rule_id 
	FROM gaming_fraud_client_events_rules
	JOIN gaming_fraud_client_events ON 
		(gaming_fraud_client_events.client_id=@client_id AND gaming_fraud_client_events.is_current=1) AND
		(gaming_fraud_client_events_rules.fraud_client_event_id=gaming_fraud_client_events.fraud_client_event_id)
  ) AS XX ON rules_temp.fraud_rule_id=XX.fraud_rule_id
  SET rules_temp.is_original_event=IF(XX.fraud_rule_id IS NULL, 1, 0), rules_temp.date_created=IF(XX.fraud_rule_id IS NULL, NOW(), rules_temp.date_created)
  WHERE rules_temp.fraud_client_event_temp_id=@fraud_client_event_temp_id;
  
  
  SET @round_row_count=1;
  SET @fraud_rule_id=-1;  
  INSERT INTO gaming_fraud_client_events_rules_temp(fraud_client_event_temp_id, fraud_rule_id, rule_points, override_points, is_original_event, date_created)
  SELECT @fraud_client_event_temp_id, tempResults.fraud_rule_id, SUM(tempResults.rule_points), SUM(tempResults.override_points), IF(SUM(tempResults.is_original_event)>=1, 1, 0), MAX(date_created)
  FROM 
  (
    SELECT @round_row_count:=IF(event_violations.fraud_rule_id!=@fraud_rule_id, 1, @round_row_count+1) AS round_row_count, @fraud_rule_id:=IF(event_violations.fraud_rule_id!=@fraud_rule_id, event_violations.fraud_rule_id, @fraud_rule_id),
      event_violations.fraud_rule_id,max_trigger_num,event_violations.rule_points,event_violations.override_points,event_violations.is_original_event , IFNULL(max_trigger_num,1) AS max_trigger, date_created
    FROM gaming_fraud_client_events_violations AS event_violations
      JOIN gaming_fraud_rules ON 
      event_violations.client_id=@client_id AND event_violations.cascade_points=1 AND
      event_violations.fraud_rule_id=gaming_fraud_rules.fraud_rule_id AND
      (
        (is_registration=1 AND @is_registration=1) OR
        (is_update_details=1 AND @is_update_details=1) OR
        (is_login=1 AND @is_login=1) OR
        (is_deposit=1 AND @is_deposit=1) OR
        (is_change_currency=1 AND @is_change_currency=1) OR
		(is_custom=1 AND @is_custom=1)
      )
      ORDER BY event_violations.fraud_rule_id, date_created
  ) AS tempResults
  WHERE round_row_count<=max_trigger 
  GROUP BY tempResults.fraud_rule_id;  

  
  UPDATE gaming_fraud_client_events_violations
  SET is_original_event = 0
  WHERE client_id = @client_id;
     
  
  
  SET @numDifferent = 0;    
  SELECT COUNT(*) INTO @numDifferent
  FROM
  (
      SELECT 
        cl_event_rules.fraud_rule_id, cl_event_rules.rule_points, cl_event_rules.override_points, 
        cl_event_rules_temp.fraud_rule_id AS fraud_rule_id_TEMP, cl_event_rules_temp.rule_points AS rule_points_TEMP, cl_event_rules_temp.override_points AS override_points_TEMP
      FROM gaming_fraud_client_events AS cl_events
      JOIN gaming_fraud_client_events_rules AS cl_event_rules ON 
        cl_events.client_id=@client_id AND cl_events.is_current=1 AND 
        cl_events.fraud_client_event_id=cl_event_rules.fraud_client_event_id
      JOIN gaming_fraud_rules ON
        cl_event_rules.fraud_rule_id=gaming_fraud_rules.fraud_rule_id AND
        (
          (is_registration=1 AND @is_registration=1) OR
          (is_update_details=1 AND @is_update_details=1) OR
          (is_login=1 AND @is_login=1) OR
          (is_deposit=1 AND @is_deposit=1) OR
          (is_change_currency=1 AND @is_change_currency=1) OR
		  (is_custom=1 AND @is_custom=1)
        )
      LEFT JOIN gaming_fraud_client_events_rules_temp AS cl_event_rules_temp ON
        cl_event_rules_temp.fraud_client_event_temp_id=@fraud_client_event_temp_id AND
        cl_event_rules.fraud_rule_id=cl_event_rules_temp.fraud_rule_id
    UNION
      SELECT  
        cl_event_rules.fraud_rule_id, cl_event_rules.rule_points, cl_event_rules.override_points,
        cl_event_rules_temp.fraud_rule_id AS fraud_rule_id_TEMP, cl_event_rules_temp.rule_points AS rule_points_TEMP, cl_event_rules_temp.override_points AS override_points_TEMP
      FROM gaming_fraud_client_events AS cl_events
      JOIN gaming_fraud_client_events_rules AS cl_event_rules ON 
        cl_events.client_id=@client_id AND cl_events.is_current=1 AND 
        cl_events.fraud_client_event_id=cl_event_rules.fraud_client_event_id
      JOIN gaming_fraud_rules ON
        cl_event_rules.fraud_rule_id=gaming_fraud_rules.fraud_rule_id AND
        (
          (is_registration=1 AND @is_registration=1) OR
          (is_update_details=1 AND @is_update_details=1) OR
          (is_login=1 AND @is_login=1) OR
          (is_deposit=1 AND @is_deposit=1) OR
          (is_change_currency=1 AND @is_change_currency=1) OR
		  (is_custom=1 AND @is_custom=1)
        )
      RIGHT OUTER JOIN gaming_fraud_client_events_rules_temp AS cl_event_rules_temp ON 
        cl_event_rules.fraud_rule_id=cl_event_rules_temp.fraud_rule_id
      WHERE cl_event_rules_temp.fraud_client_event_temp_id=@fraud_client_event_temp_id 
  ) AS XX
  WHERE 
    fraud_rule_id IS NULL OR 
    fraud_rule_id_TEMP IS NULL OR 
    rule_points<>rule_points_TEMP OR
    IFNULL(override_points,-1)<>IFNULL(override_points_TEMP,-1);  
   

  
  UPDATE gaming_fraud_client_events_temp AS cl_events_temp
  JOIN
  (
    SELECT SUM(rule_points) AS rule_points, SUM(IFNULL(override_points,rule_points)) AS override_points
    FROM
    (
        SELECT @fraud_client_event_temp_id, gaming_fraud_rules.fraud_rule_id, cl_event_rules.rule_points, cl_event_rules.override_points
        FROM gaming_fraud_client_events AS cl_events
        JOIN gaming_fraud_client_events_rules AS cl_event_rules ON 
          cl_events.client_id=@client_id AND cl_events.is_current=1 AND 
          cl_events.fraud_client_event_id=cl_event_rules.fraud_client_event_id
        JOIN gaming_fraud_rules ON
          cl_event_rules.fraud_rule_id=gaming_fraud_rules.fraud_rule_id AND
          (
            ((is_registration=1 AND @is_registration=0) AND (is_login=0 OR @is_login=0) AND (is_update_details=0 OR @is_update_details=0) AND (is_deposit=0 OR @is_deposit=0) AND (is_custom=0 OR @is_custom=0)) OR
            ((is_update_details=1 AND @is_update_details=0) AND (is_registration=0 OR @is_registration=0) AND (is_login=0 OR @is_login=0) AND (is_deposit=0 OR @is_deposit=0) AND (is_custom=0 OR @is_custom=0)) OR
            ((is_login=1 AND @is_login=0) AND (is_registration=0 OR @is_registration=0) AND (is_update_details=0 OR @is_update_details=0) AND (is_deposit=0 OR @is_deposit=0) AND (is_custom=0 OR @is_custom=0)) OR
            ((is_deposit=1 AND @is_deposit=0) AND (is_registration=0 OR @is_registration=0) AND (is_login=0 OR @is_login=0) AND (is_update_details=0 OR @is_update_details=0) AND (is_custom=0 OR @is_custom=0)) OR
            (is_change_currency=1 AND @is_change_currency=0) OR
			(is_custom=1 AND @is_custom=1)
          )
      UNION  
        SELECT @fraud_client_event_id, fraud_rule_id, rule_points, override_points
        FROM gaming_fraud_client_events_rules_temp 
        WHERE fraud_client_event_temp_id=@fraud_client_event_temp_id
    ) AS XX
  ) AS total_points ON 1=1
  JOIN gaming_fraud_classification_types AS cls_types ON cls_types.is_active=1 AND
    total_points.override_points >= cls_types.points_min_range AND total_points.override_points < IFNULL(cls_types.points_max_range,2147483647)
  SET
    cl_events_temp.rule_points=total_points.rule_points, 
    cl_events_temp.override_points=total_points.override_points, 
    cl_events_temp.fraud_classification_type_id=cls_types.fraud_classification_type_id,
    is_different = (@numDifferent > 0),
    fraud_client_event_id = IF(@numDifferent > 0, @fraud_client_event_id, NULL)
  WHERE fraud_client_event_temp_id=@fraud_client_event_temp_id;
  
  
  
  
  
    
  
  IF (@numDifferent > 0) THEN
  
    
    INSERT INTO gaming_fraud_client_events_rules (fraud_client_event_id, fraud_rule_id, rule_points, override_points, is_original_event, original_event_date)
    SELECT @fraud_client_event_id, gaming_fraud_rules.fraud_rule_id, cl_event_rules.rule_points, cl_event_rules.override_points, 0, cl_event_rules.original_event_date 
    FROM gaming_fraud_client_events AS cl_events
    JOIN gaming_fraud_client_events_rules AS cl_event_rules ON 
      cl_events.client_id=@client_id AND cl_events.is_current=1 AND 
      cl_events.fraud_client_event_id=cl_event_rules.fraud_client_event_id
    JOIN gaming_fraud_rules ON
      cl_event_rules.fraud_rule_id=gaming_fraud_rules.fraud_rule_id AND
      (
        ((is_registration=1 AND @is_registration=0) AND (is_login=0 OR @is_login=0) AND (is_update_details=0 OR @is_update_details=0) AND (is_deposit=0 OR @is_deposit=0) AND (is_custom=0 OR @is_custom=0)) OR
        ((is_update_details=1 AND @is_update_details=0) AND (is_registration=0 OR @is_registration=0) AND (is_login=0 OR @is_login=0) AND (is_deposit=0 OR @is_deposit=0) AND (is_custom=0 OR @is_custom=0)) OR
        ((is_login=1 AND @is_login=0) AND (is_registration=0 OR @is_registration=0) AND (is_update_details=0 OR @is_update_details=0) AND (is_deposit=0 OR @is_deposit=0) AND (is_custom=0 OR @is_custom=0)) OR
        ((is_deposit=1 AND @is_deposit=0) AND (is_registration=0 OR @is_registration=0) AND (is_login=0 OR @is_login=0) AND (is_update_details=0 OR @is_update_details=0) AND (is_custom=0 OR @is_custom=0)) OR
        (is_change_currency=1 AND @is_change_currency=0) OR
		(is_custom=1 AND @is_custom=0)
      )
    WHERE gaming_fraud_rules.fraud_rule_id NOT IN (SELECT fraud_rule_id
                                                    FROM gaming_fraud_client_events_rules_temp 
                                                    WHERE fraud_client_event_temp_id=@fraud_client_event_temp_id);
    
    
	
    INSERT INTO gaming_fraud_client_events_rules(fraud_client_event_id, fraud_rule_id, rule_points, override_points, is_original_event, original_event_date)
    SELECT @fraud_client_event_id, rules_temp.fraud_rule_id, rules_temp.rule_points, rules_temp.override_points, rules_temp.is_original_event, IF (rules_temp.is_original_event, NOW(), rules_temp.date_created)
    FROM gaming_fraud_client_events_rules_temp AS rules_temp
    WHERE rules_temp.fraud_client_event_temp_id=@fraud_client_event_temp_id;
  
	
	SELECT fraud_classification_type_id INTO fraudClassificationTypeIDPrev
    FROM gaming_fraud_client_events
	WHERE gaming_fraud_client_events.client_id=@client_id AND gaming_fraud_client_events.is_current=1;

	
    
    UPDATE gaming_fraud_client_events
    SET is_current=0 
    WHERE gaming_fraud_client_events.client_id=@client_id AND gaming_fraud_client_events.is_current=1;
    
	
    
    UPDATE gaming_fraud_client_events AS client_event
    LEFT JOIN
    (
      SELECT SUM(rule_points) AS rule_points, SUM(IFNULL(override_points,rule_points)) AS override_points 
      FROM gaming_fraud_client_events_rules
      WHERE gaming_fraud_client_events_rules.fraud_client_event_id=@fraud_client_event_id
    ) AS total_points ON 1=1
    JOIN gaming_fraud_classification_types AS cls_types ON cls_types.is_active=1 AND
      IFNULL(total_points.override_points, 0) >= cls_types.points_min_range AND IFNULL(total_points.override_points, 0) < IFNULL(cls_types.points_max_range,2147483647)
    SET 
      client_event.rule_points=IFNULL(total_points.rule_points, 0), 
      client_event.override_points=IFNULL(total_points.override_points, 0), 
      client_event.fraud_classification_type_id=cls_types.fraud_classification_type_id,
      client_event.is_current=1
    WHERE client_event.fraud_client_event_id=@fraud_client_event_id; 

    
	SELECT fraud_classification_type_id INTO fraudClassificationTypeIDNew
    FROM gaming_fraud_client_events
	WHERE gaming_fraud_client_events.client_id=@client_id AND gaming_fraud_client_events.is_current=1;
    
	SELECT gs1.value_bool as vb1 INTO notificationEnabled
	FROM gaming_settings gs1 
	WHERE gs1.name='NOTIFICATION_ENABLED';

	IF (notificationEnabled) THEN
		IF(fraudClassificationTypeIDPrev != fraudClassificationTypeIDNew) THEN
			INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
			VALUES (203, @client_id, fraudClassificationTypeIDNew, 0) ON DUPLICATE KEY UPDATE is_processing=0, event2_id=VALUES(event2_id);
		END IF;
	END IF;

  ELSE
  
    
    
    DELETE FROM gaming_fraud_client_events
    WHERE fraud_client_event_id=@fraud_client_event_id;
    
  END IF;
    
  
  DELETE FROM gaming_fraud_client_events_rules_temp WHERE fraud_client_event_temp_id=@fraud_client_event_temp_id;

    
  
  SELECT kickout INTO @kickout  
  FROM gaming_fraud_client_events
  JOIN gaming_fraud_classification_types ON
    gaming_fraud_client_events.client_id=@client_id AND gaming_fraud_client_events.is_current=1 AND
    gaming_fraud_client_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id;
  
  
  IF (@kickout=1) THEN
    CALL SessionKickoutPlayerByCloseType(@session_id,@client_id,@client_stat_id,'FraudKickout');
  END IF;
  
  SET statusCode=0;
  
END root$$

DELIMITER ;

