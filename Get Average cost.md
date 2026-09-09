## X++
public class InventSumQuery  
{      
    static void main(Args _args)  
    {  
        Qty                     totalQty;  
        Query                   query;  
        QueryRun                queryRun;  
        QueryBuildDataSource    qbdsInventDim, qbdsInventSum;  
        InventSum               inventSum;  
     
        query = new query();  
  
        qbdsInventSum = query.addDataSource(tableNum(InventSum));  
        qbdsInventDim = qbdsInventSum.addDataSource(tableNum(InventDim));  
        qbdsInventDim.relations(true);  
        qbdsInventDim.joinMode(JoinMode::InnerJoin);  
        qbdsInventDim.addRange(fieldNum(InventDim, InventSiteId)).value("");  
        qbdsInventDim.addRange(fieldNum(InventDim, InventLocationId)).value("");  
        qbdsInventDim.addRange(fieldNum(InventDim, wmsLocationId)).value("");  
        qbdsInventSum.addGroupByField(fieldNum(InventSum, ItemId));  
  
        qbdsInventSum.addSelectionField(fieldNum(InventSum, PostedQty), SelectionField::Sum);  
        qbdsInventSum.addSelectionField(fieldNum(InventSum, Deducted), SelectionField::Sum);  
        qbdsInventSum.addSelectionField(fieldNum(InventSum, Received), SelectionField::Sum);  
        qbdsInventSum.addSelectionField(fieldNum(InventSum, PostedValue), SelectionField::Sum);  
        qbdsInventSum.addSelectionField(fieldNum(InventSum, PhysicalValue), SelectionField::Sum);  
      
        qbdsInventSum.addRange(fieldNum(InventSum, ItemId)).value("");  
  
        queryrun = new QueryRun(query);  
  
        while (queryRun.next())  
        {  
            queryRun.changed(tableNum(InventSum));  
            {  
                inventSum = queryRun.get(tableNum(InventSum));  
                totalQty = inventSum.PostedQty - abs(inventSum.Deducted)   inventSum.Received;  
                totalQty = abs(inventSum.PostedValue   inventSum.PhysicalValue) / totalQty;  
                info(strFmt("Average unit cost - %1", totalQty));  
            }  
        }  
    }  
  
}


## SQL

SELECT   
    s.itemid,  
    SUM(s.postedqty) AS TotalPostedQty,  
    SUM(s.deducted) AS TotalDeducted,  
    SUM(s.received) AS TotalReceived,  
    SUM(s.postedvalue) AS TotalPostedValue,  
    SUM(s.physicalvalue) AS TotalPhysicalValue,  
    (SUM(s.postedqty) - ABS(SUM(s.deducted)) + SUM(s.received)) AS TotalQtyCalc,  
    CASE   
        WHEN (SUM(s.postedqty) - ABS(SUM(s.deducted)) + SUM(s.received)) = 0 THEN 0  
        ELSE ABS(SUM(s.postedvalue) + SUM(s.physicalvalue))   
             / NULLIF((SUM(s.postedqty) - ABS(SUM(s.deducted)) + SUM(s.received)), 0)  
    END AS AverageUnitCost  
FROM bronze_d365.inventsum s  
INNER JOIN bronze_d365.inventdim d  
    ON s.inventdimid = d.inventdimid  
   AND s.dataareaid = d.dataareaid  
WHERE s.itemid = 'RP100033'  
  AND LOWER(s.dataareaid) = 'rsau'  
GROUP BY s.itemid;