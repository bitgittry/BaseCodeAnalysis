DROP procedure IF EXISTS `ClientSegmentAutoUpdatePlayersSegments`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `ClientSegmentAutoUpdatePlayersSegments`()
root:BEGIN

  DECLARE clientSegmentCounterID, clientSegmentGroupID BIGINT DEFAULT -1;
  DECLARE numDays INT DEFAULT 0;
  DECLARE realMoneyOnly TINYINT(1) DEFAULT 0;

  SET clientSegmentGroupID=-1;
  SET clientSegmentCounterID=-1;
  SET numDays=0;
  SELECT client_segment_group_id, num_days INTO clientSegmentGroupID, numDays FROM gaming_client_segment_groups WHERE `name`='DynamicCRM' AND is_active AND is_dynamic;
  
  IF (clientSegmentGroupID!=-1) THEN
    INSERT INTO gaming_client_segment_counter (client_segment_group_id, created_date)
    SELECT clientSegmentGroupID, NOW();

    SET clientSegmentCounterID=LAST_INSERT_ID();
    SET @inactiveDate=(DATE_SUB(NOW(), INTERVAL IFNULL(numDays, 60) DAY));
    
    INSERT INTO gaming_client_segment_counter_players (client_segment_counter_id, client_id, client_segment_id)
    SELECT clientSegmentCounterID, gaming_clients.client_id, new_segment.client_segment_id 
    FROM gaming_client_stats
    JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active AND 
      gaming_clients.is_active 
	LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id 
    JOIN gaming_client_segments AS new_segment ON new_segment.client_segment_group_id=clientSegmentGroupID AND (CASE
      WHEN num_deposits = 0 THEN 'NRC'
      WHEN num_deposits = 1 THEN 'NDC'
      WHEN num_deposits > 1 AND (last_played_date IS NOT NULL AND last_played_date>@inactiveDate) THEN 'Active'
      WHEN num_deposits > 1 AND (last_played_date IS NULL OR last_played_date<=@inactiveDate) THEN 'InActive'
      ELSE 'InActive'
     END)=new_segment.name
    LEFT JOIN gaming_client_segments_players AS current_segment ON current_segment.client_segment_group_id=clientSegmentGroupID AND (current_segment.client_id=gaming_clients.client_id AND current_segment.is_current)
    WHERE new_segment.client_segment_id IS NOT NULL AND (current_segment.client_segment_id IS NULL OR new_segment.client_segment_id!=current_segment.client_segment_id) AND (gaming_clients.is_account_closed=0 AND gaming_fraud_rule_client_settings.block_account = 0); 

    CALL ClientSegmentUpdatePlayersSegmentFromCounter(clientSegmentCounterID,  clientSegmentGroupID);
  END IF;

  SET clientSegmentGroupID=-1;
  SET clientSegmentCounterID=-1;
  SET numDays=0;
  SELECT client_segment_group_id, num_days INTO clientSegmentGroupID, numDays FROM gaming_client_segment_groups WHERE `name`='DynamicDepositAmount' AND is_active AND is_dynamic;
  
  IF (clientSegmentGroupID!=1) THEN
    INSERT INTO gaming_client_segment_counter (client_segment_group_id, created_date)
    SELECT clientSegmentGroupID, NOW();

    SET clientSegmentCounterID=LAST_INSERT_ID();
    SET @startDate=(DATE_SUB(NOW(), INTERVAL IFNULL(numDays, 60) DAY));
    
    INSERT INTO gaming_client_segment_counter_players (client_segment_counter_id, client_id, client_segment_id)
    SELECT clientSegmentCounterID, gaming_clients.client_id, new_segment.client_segment_id 
    FROM gaming_client_stats
    JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active AND 
      gaming_clients.is_active 
	LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id 
    LEFT JOIN
    (
      SELECT client_stat_id, SUM(amount_total_base) AS Amount
      FROM gaming_transactions 
      WHERE timestamp>=@startDate AND payment_transaction_type_id IN (1,22) 
      GROUP BY client_stat_id
    ) AS Transactions ON gaming_client_stats.client_stat_id=Transactions.client_stat_id
    JOIN gaming_client_segments AS new_segment ON new_segment.client_segment_group_id=clientSegmentGroupID AND 
      IFNULL(Transactions.Amount,0) BETWEEN new_segment.range_min AND IFNULL(new_segment.range_max,100000000000)
    LEFT JOIN gaming_client_segments_players AS current_segment ON current_segment.client_segment_group_id=clientSegmentGroupID AND (current_segment.client_id=gaming_clients.client_id AND current_segment.is_current)
    WHERE new_segment.client_segment_id IS NOT NULL AND (current_segment.client_segment_id IS NULL OR new_segment.client_segment_id!=current_segment.client_segment_id) AND (gaming_clients.is_account_closed=0 AND gaming_fraud_rule_client_settings.block_account = 0); 
  
    CALL ClientSegmentUpdatePlayersSegmentFromCounter(clientSegmentCounterID,  clientSegmentGroupID);
  END IF;

  SET clientSegmentGroupID=-1;
  SET clientSegmentCounterID=-1;
  SET numDays=0;
  SELECT client_segment_group_id, num_days, IFNULL(real_money_only,0) INTO clientSegmentGroupID, numDays, realMoneyOnly FROM gaming_client_segment_groups WHERE `name`='DynamicBetAmount' AND is_active AND is_dynamic;
  
  IF (clientSegmentGroupID!=1) THEN
    INSERT INTO gaming_client_segment_counter (client_segment_group_id, created_date)
    SELECT clientSegmentGroupID, NOW();

    SET clientSegmentCounterID=LAST_INSERT_ID();
    SET @startDate=(DATE_SUB(NOW(), INTERVAL IFNULL(numDays, 60) DAY));
    
    INSERT INTO gaming_client_segment_counter_players (client_segment_counter_id, client_id, client_segment_id)
    SELECT clientSegmentCounterID, gaming_clients.client_id, new_segment.client_segment_id 
    FROM gaming_client_stats
    JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active AND 
      gaming_clients.is_active
	LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id 
    LEFT JOIN
    (
      SELECT client_stat_id, SUM(IF(realMoneyOnly, bet_real, bet_total)) AS Amount
      FROM gaming_game_transactions_aggregation_player_game 
      WHERE date_from>=@startDate 
      GROUP BY client_stat_id
    ) AS Transactions ON gaming_client_stats.client_stat_id=Transactions.client_stat_id
    JOIN gaming_client_segments AS new_segment ON new_segment.client_segment_group_id=clientSegmentGroupID AND 
      IFNULL(Transactions.Amount,0) BETWEEN new_segment.range_min AND IFNULL(new_segment.range_max,100000000000)
    LEFT JOIN gaming_client_segments_players AS current_segment ON current_segment.client_segment_group_id=clientSegmentGroupID AND (current_segment.client_id=gaming_clients.client_id AND current_segment.is_current)
    WHERE new_segment.client_segment_id IS NOT NULL AND (current_segment.client_segment_id IS NULL OR new_segment.client_segment_id!=current_segment.client_segment_id) AND (gaming_clients.is_account_closed=0 AND gaming_fraud_rule_client_settings.block_account = 0); 
  
    CALL ClientSegmentUpdatePlayersSegmentFromCounter(clientSegmentCounterID,  clientSegmentGroupID);
  END IF;

END root$$

DELIMITER ;

