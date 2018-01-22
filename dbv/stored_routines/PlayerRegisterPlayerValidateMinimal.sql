DROP procedure IF EXISTS `PlayerRegisterPlayerValidateMinimal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerRegisterPlayerValidateMinimal`(affiliateExternalID VARCHAR(80), affiliateSystemName VARCHAR(80), bonusCouponCode VARCHAR(80))
BEGIN
  
  SELECT affiliate_id, affiliate_system_id, COUNT(*)
  INTO @affiliateID, @affiliateSystemIDFromAffiliate, @numAffiliates 
  FROM gaming_affiliates  FORCE INDEX (external_id)
  WHERE external_id=affiliateExternalID AND is_active=1;
  
  SELECT bonus_coupon_id, COUNT(*) INTO @bonusCouponID, @numBonusCoupons 
  FROM gaming_bonus_coupons  FORCE INDEX (coupon_code)
  WHERE coupon_code=bonusCouponCode AND (NOW() BETWEEN validity_start_date AND validity_end_date) AND is_active=1 AND is_hidden=0;
  
  SELECT bonus_coupon_id INTO @defaultBonusCouponID 
  FROM gaming_bonus_coupons FORCE INDEX (default_registration_coupon)
  WHERE default_registration_coupon=1 LIMIT 1;
  
  SELECT @numAffiliates, @affiliateID, @affiliateSystemIDFromAffiliate,
    @numBonusCoupons, @bonusCouponID, @defaultBonusCouponID;  
    
END$$

DELIMITER ;

