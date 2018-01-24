DROP view IF EXISTS `vw_period_daily_balances`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` VIEW `vw_period_daily_balances` AS
    select 
        `params`.`session_code` AS `session_code`,
        `balstart`.`client_stat_id` AS `client_stat_id`,
        `balstart`.`client_id` AS `client_id`,
        ifnull(`balstart`.`real_balance`, 0) AS `start_real_balance`,
        ifnull(`balstart`.`bonus_balance`, 0) AS `start_bonus_balance`,
        ifnull(`balstart`.`bonus_win_locked_balance`, 0) AS `start_bonus_win_locked`,
        ifnull(`balstart`.`pending_withdrawals`, 0) AS `start_pending_withdrawals`,
        ifnull(`balstart`.`pending_bets_real`, 0) AS `start_pending_bets_real`,
        ifnull(`balstart`.`pending_bets_bonus`, 0) AS `start_pending_bets_bonus`,
        ifnull(`balstart`.`exchange_rate`, 1) AS `start_exchange_rate`,
        ifnull(`balstart`.`loyalty_points_balance`, 0) AS `start_loyalty_points_balance`,
        ifnull(`balend`.`real_balance`, 0) AS `end_real_balance`,
        ifnull(`balend`.`bonus_balance`, 0) AS `end_bonus_balance`,
        ifnull(`balend`.`bonus_win_locked_balance`, 0) AS `end_bonus_win_locked`,
        ifnull(`balend`.`pending_withdrawals`, 0) AS `end_pending_withdrawals`,
        ifnull(`balend`.`pending_bets_real`, 0) AS `end_pending_bets_real`,
        ifnull(`balend`.`pending_bets_bonus`, 0) AS `end_pending_bets_bonus`,
        ifnull(`balend`.`exchange_rate`, 1) AS `end_exchange_rate`,
        ifnull(`balend`.`loyalty_points_balance`, 0) AS `end_loyalty_points_balance`,
        (ifnull(`balstart`.`real_balance`, 0) / ifnull(`exchange_rate_start`.`exchange_rate`, 1)) AS `start_real_balance_base`,
        (ifnull(`balstart`.`bonus_balance`, 0) / ifnull(`exchange_rate_start`.`exchange_rate`, 1)) AS `start_bonus_balance_base`,
        (ifnull(`balstart`.`bonus_win_locked_balance`, 0) / ifnull(`exchange_rate_start`.`exchange_rate`, 1)) AS `start_bonus_win_locked_base`,
        (ifnull(`balstart`.`pending_withdrawals`, 0) / ifnull(`exchange_rate_start`.`exchange_rate`, 1)) AS `start_pending_withdrawals_base`,
        (ifnull(`balstart`.`pending_bets_real`, 0) / ifnull(`exchange_rate_start`.`exchange_rate`, 1)) AS `start_pending_bets_real_base`,
        (ifnull(`balstart`.`pending_bets_bonus`, 0) / ifnull(`exchange_rate_start`.`exchange_rate`, 1)) AS `start_pending_bets_bonus_base`,
        (ifnull(`balend`.`real_balance`, 0) / ifnull(`exchange_rate_end`.`exchange_rate`, 1)) AS `end_real_balance_base`,
        (ifnull(`balend`.`bonus_balance`, 0) / ifnull(`exchange_rate_end`.`exchange_rate`, 1)) AS `end_bonus_balance_base`,
        (ifnull(`balend`.`bonus_win_locked_balance`, 0) / ifnull(`exchange_rate_end`.`exchange_rate`, 1)) AS `end_bonus_win_locked_base`,
        (ifnull(`balend`.`pending_withdrawals`, 0) / ifnull(`exchange_rate_end`.`exchange_rate`, 1)) AS `end_pending_withdrawals_base`,
        (ifnull(`balend`.`pending_bets_real`, 0) / ifnull(`exchange_rate_end`.`exchange_rate`, 1)) AS `end_pending_bets_real_base`,
        (ifnull(`balend`.`pending_bets_bonus`, 0) / ifnull(`exchange_rate_end`.`exchange_rate`, 1)) AS `end_pending_bets_bonus_base`
    from
        (((((`gaming_client_daily_balances` `balstart`
        left join `gaming_client_daily_balances` `balend` ON ((`balstart`.`client_stat_id` = `balend`.`client_stat_id`)))
        join `vw_period_daily_balances_params` `params` ON (((`params`.`From_Date` between (`balstart`.`date_from_int` + 1) and `balstart`.`date_to_int`)
            and (`params`.`To_Date` between (`balend`.`date_from_int` + 1) and `balend`.`date_to_int`))))
        left join `history_gaming_operator_currency` `exchange_rate_start` FORCE INDEX (operator_id) FORCE INDEX (currency_id) ON (((`params`.`From_Date` between (to_days(`exchange_rate_start`.`history_datetime_from`) + 1) and to_days(`exchange_rate_start`.`history_datetime_to`))
            and (`balstart`.`currency_id` = `exchange_rate_start`.`currency_id`)
            and (`exchange_rate_start`.`operator_id` = `params`.`Operator_ID`))))
        left join `history_gaming_operator_currency` `exchange_rate_end` FORCE INDEX (operator_id) FORCE INDEX (currency_id) ON (((`params`.`To_Date` between (to_days(`exchange_rate_end`.`history_datetime_from`) + 1) and to_days(`exchange_rate_end`.`history_datetime_to`))
            and (`balend`.`currency_id` = `exchange_rate_end`.`currency_id`)
            and (`exchange_rate_end`.`operator_id` = `params`.`Operator_ID`))))
        join `gaming_operator_currency` ON (((`balstart`.`currency_id` = `gaming_operator_currency`.`currency_id`)
            and (`balend`.`currency_id` = `gaming_operator_currency`.`currency_id`))))
$$

DELIMITER ;