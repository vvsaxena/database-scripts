SELECT case when @r=pti.invoice_id then NULL else pti.invoice_id end as "ptinvd",
case when @r=pti.invoice_id then @p+pti.amount_used else pti.amount_used end as "Total Sum",
case when pti.created_at < Date_add(i.created_at, interval 9 day) then "Y" else "N" end as "Total Sum1",
pti.created_at,
@r := pti.invoice_id,
@p := pti.amount_used
FROM   ( SELECT @r := 0 ) vars,(SELECT @p := 0) vars1, payment_to_invoice pti, invoices i
WHERE  pti.invoice_id = i.id
AND    pti.status = 'active'
order by pti.invoice_id
;
