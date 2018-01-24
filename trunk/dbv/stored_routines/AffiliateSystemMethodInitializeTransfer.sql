DROP procedure IF EXISTS `AffiliateSystemMethodInitializeTransfer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `AffiliateSystemMethodInitializeTransfer`(affiliateSystemID BIGINT, affiliateSystemMethodType VARCHAR(80), queryDateIntervalID BIGINT, testOnly TINYINT(1), OUT statusCode INT)
root: BEGIN
  
 
  DECLARE affiliateSystemIDCheck, affiliateSystemMethodID, queryDateIntervalIDCheck, affiliateSystemMethodCallID BIGINT DEFAULT -1; 
  DECLARE intervalDateFrom DATETIME DEFAULT NULL; 
   
  
  
  SELECT affiliate_system_id INTO affiliateSystemIDCheck
  FROM gaming_affiliate_systems
  WHERE gaming_affiliate_systems.affiliate_system_id=affiliateSystemID;
  
  SELECT affiliate_system_method_id INTO affiliateSystemMethodID
  FROM gaming_affiliate_system_method_types  
  JOIN gaming_affiliate_system_methods ON 
    gaming_affiliate_system_method_types.method_type=affiliateSystemMethodType AND
    gaming_affiliate_system_methods.affiliate_system_id=affiliateSystemID AND 
    gaming_affiliate_system_method_types.affiliate_system_method_type_id=gaming_affiliate_system_methods.affiliate_system_method_type_id;  
    
  SELECT gaming_query_date_intervals.query_date_interval_id, gaming_query_date_intervals.date_from
  INTO queryDateIntervalIDCheck, intervalDateFrom
  FROM gaming_query_date_interval_types
  JOIN gaming_query_date_intervals ON 
    gaming_query_date_intervals.query_date_interval_id=queryDateIntervalID AND 
    gaming_query_date_interval_types.query_date_interval_type_id=gaming_query_date_intervals.query_date_interval_type_id
  WHERE query_date_interval_id=queryDateIntervalID;
  
  IF (affiliateSystemID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (affiliateSystemMethodID=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
 
  
  IF (queryDateIntervalIDCheck=-1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (intervalDateFrom>NOW() AND testOnly =0) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
 
  
  INSERT INTO gaming_affiliate_system_method_calls (affiliate_system_method_id, affiliate_system_id, query_date_interval_id, start_date, execution_status_id)
  SELECT affiliateSystemMethodID, affiliateSystemID, queryDateIntervalID, NOW(), execution_status_id
  FROM gaming_execution_statuses
  WHERE name='InProgress';
    
  SET affiliateSystemMethodCallID=LAST_INSERT_ID(); 
  
  
  
  
  SELECT affiliate_system_method_call_id, affiliate_system_method_id, query_date_interval_id, start_date, end_date, method_calls.execution_status_id, gaming_execution_statuses.name AS execution_status, data_transferred
  FROM gaming_affiliate_system_method_calls AS method_calls
  JOIN gaming_execution_statuses ON method_calls.execution_status_id=gaming_execution_statuses.execution_status_id
  WHERE affiliate_system_method_call_id=affiliateSystemMethodCallID;
  
  SET statusCode=0;
END root$$

DELIMITER ;

