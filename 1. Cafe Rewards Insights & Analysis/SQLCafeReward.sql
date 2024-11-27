USE [Cafe Rewards Offers]
GO

-- Tạo khóa ngoại giữa bảng events và customers
ALTER TABLE [dbo].[events]
ADD CONSTRAINT FK_events_customers
FOREIGN KEY (customer_id) REFERENCES [dbo].[customers](customer_id)
ON DELETE CASCADE ON UPDATE CASCADE;
GO

-- Tạo khóa ngoại giữa bảng events và offers
ALTER TABLE [dbo].[events]
ADD CONSTRAINT FK_events_offers
FOREIGN KEY (offer_id) REFERENCES [dbo].[offers](offer_id)
ON DELETE SET NULL ON UPDATE CASCADE;
GO

-- I. Offer Performance Analysis
-- 1. Analyzing Offer Type Performance
WITH ValidEvents AS (
   SELECT * 
   FROM events
   WHERE valid_completion = 'True'
),
OfferMetrics AS (
   SELECT 
       o.offer_type,
       COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN e.customer_id END) as Total_Sent,
       COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN e.customer_id END) as Total_Viewed,
       COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN e.customer_id END) as Total_Completed
   FROM ValidEvents e
   JOIN offers o ON e.offer_id = o.offer_id
   GROUP BY o.offer_type
)

SELECT
   offer_type,
   Total_Sent,
   Total_Viewed,
   Total_Completed,
   -- Tính các rates
   ROUND(CAST(Total_Viewed AS FLOAT) / NULLIF(Total_Sent, 0) * 100, 2) as [View Rate (%)],
   ROUND(CAST(Total_Completed AS FLOAT) / NULLIF(Total_Viewed, 0) * 100, 2) as [Completion Rate (%)],
   ROUND(CAST(Total_Completed AS FLOAT) / NULLIF(Total_Sent, 0) * 100, 2) as [Success Rate (%)]
FROM OfferMetrics
ORDER BY offer_type;

--2. Offer Difficulty Effectiveness
WITH ValidOffers AS (
   SELECT *
   FROM events e
   WHERE e.offer_id IS NOT NULL 
),
DifficultyMetrics AS (
   -- Calculate metrics for each difficulty level
   SELECT 
       o.difficulty,
       COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN e.customer_id END) as Total_Sent,
       COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN e.customer_id END) as Total_Viewed,
       COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN e.customer_id END) as Total_Completed
   FROM ValidOffers e
   JOIN offers o ON e.offer_id = o.offer_id
   GROUP BY o.difficulty
)

SELECT 
   CONCAT('$', difficulty) as Spend_Level,
   Total_Sent,
   Total_Viewed,
   Total_Completed,
   -- Calculate rates
   ROUND(CAST(Total_Viewed AS FLOAT) / NULLIF(Total_Sent, 0) * 100, 2) as [View Rate (%)],
   ROUND(CAST(Total_Completed AS FLOAT) / NULLIF(Total_Viewed, 0) * 100, 2) as [Completion Rate (%)],
   ROUND(CAST(Total_Completed AS FLOAT) / NULLIF(Total_Sent, 0) * 100, 2) as [Success Rate (%)]
FROM DifficultyMetrics
ORDER BY difficulty;

-- Calculate ROI
WITH CompletedOffers AS (
   SELECT 
       o.difficulty,
       COUNT(*) as num_completions,
       SUM(CAST(o.reward AS FLOAT)) as total_reward,
       o.difficulty * COUNT(*) as total_required_spend
   FROM events e
   JOIN offers o ON e.offer_id = o.offer_id 
   WHERE e.event = 'offer completed'
   GROUP BY o.difficulty
)

SELECT
   CONCAT('$', difficulty) as Spend_Level,
   num_completions as [Number of Completions],
   total_reward as [Total Reward],
   total_required_spend as [Total Required Spend],
   ROUND(CASE 
       WHEN total_required_spend > 0 
       THEN (total_reward / total_required_spend * 100)
       ELSE 0 
   END, 2) as [ROI (%)]
FROM CompletedOffers
ORDER BY difficulty;

-- 3. REWARD EFFECTIVENESS
WITH ValidEvents AS (
   SELECT e.*, o.reward as reward_offer, o.offer_type
   FROM events e
   INNER JOIN offers o ON e.offer_id = o.offer_id
   WHERE e.valid_completion = 'True'
),
RewardMetrics AS (
   -- Calculate metrics for each reward level
   SELECT 
       o.reward,
       COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN e.customer_id END) as Total_Sent,
       COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN e.customer_id END) as Total_Viewed,
       COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN e.customer_id END) as Total_Completed
   FROM ValidEvents e
   JOIN offers o ON e.offer_id = o.offer_id
   GROUP BY o.reward
)

SELECT
   CONCAT('$', reward) as Reward_Level,
   Total_Sent,
   Total_Viewed,
   Total_Completed,
   -- Calculate rates
   ROUND(CAST(Total_Viewed AS FLOAT) / NULLIF(Total_Sent, 0) * 100, 2) as [View Rate (%)],
   ROUND(CAST(Total_Completed AS FLOAT) / NULLIF(Total_Viewed, 0) * 100, 2) as [Completion Rate (%)],
   ROUND(CAST(Total_Completed AS FLOAT) / NULLIF(Total_Sent, 0) * 100, 2) as [Success Rate (%)]
FROM RewardMetrics
WHERE Total_Sent > 0
ORDER BY reward;


--4. CHANNEL EFFECTIVENESS
WITH SplitChannels AS (
    SELECT DISTINCT
        offer_id,
        TRIM(value) as channel
    FROM offers
    CROSS APPLY STRING_SPLIT(
        REPLACE(REPLACE(channels, '[', ''), ']', ''),
        ','
    )
),
ChannelMetrics AS (
    SELECT 
        c.channel,
        COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN e.customer_id END) as Total_Sent,
        COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN e.customer_id END) as Total_Viewed,
        COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN e.customer_id END) as Total_Completed
    FROM SplitChannels c
    JOIN events e ON c.offer_id = e.offer_id 
    WHERE e.valid_completion = 'True'
    GROUP BY c.channel
)

SELECT
    channel,
    Total_Sent,
    Total_Viewed,
    Total_Completed,
    ROUND(CAST(Total_Viewed AS FLOAT) / NULLIF(Total_Sent, 0) * 100, 2) as [View Rate (%)],
    ROUND(CAST(Total_Completed AS FLOAT) / NULLIF(Total_Viewed, 0) * 100, 2) as [Completion Rate (%)],
    ROUND(CAST(Total_Completed AS FLOAT) / NULLIF(Total_Sent, 0) * 100, 2) as [Success Rate (%)]
FROM ChannelMetrics
WHERE Total_Sent > 0
ORDER BY channel;

--II. Customer Segment
-- 1. Analyze Age Group
WITH CustomerDemographics AS (
    SELECT
        c.customer_id,
        c.age,
        c.income,
        c.gender,
        e.offer_id,
        o.offer_type,
        o.difficulty
    FROM customers c
    INNER JOIN events e ON c.customer_id = e.customer_id
    INNER JOIN offers o ON e.offer_id = o.offer_id
    WHERE e.valid_completion = 'True'
)
SELECT
    CASE
        WHEN age < 25 THEN '18-25'
        WHEN age BETWEEN 26 AND 35 THEN '26-35'
        WHEN age BETWEEN 36 AND 45 THEN '36-45'
        WHEN age BETWEEN 46 AND 55 THEN '46-55'
        WHEN age BETWEEN 56 AND 65 THEN '56-65'
        ELSE '65+'
    END AS age_group,
    COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN c.customer_id END) AS Total_Sent,
    COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN c.customer_id END) AS Total_Viewed,
    COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN c.customer_id END) AS Total_Completed,
    ROUND(CAST(COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN c.customer_id END) AS FLOAT) / NULLIF(COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN c.customer_id END), 0) * 100, 2) AS [View Rate (%)],
    ROUND(CAST(COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN c.customer_id END) AS FLOAT) / NULLIF(COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN c.customer_id END), 0) * 100, 2) AS [Completion Rate (%)],
    ROUND(CAST(COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN c.customer_id END) AS FLOAT) / NULLIF(COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN c.customer_id END), 0) * 100, 2) AS [Success Rate (%)],
    ROUND(AVG(CAST(e.amount AS FLOAT)), 2) AS [Avg Spend]
FROM CustomerDemographics c
INNER JOIN events e ON c.customer_id = e.customer_id
GROUP BY
    CASE
        WHEN c.age < 25 THEN '18-25'
        WHEN c.age BETWEEN 26 AND 35 THEN '26-35'
        WHEN c.age BETWEEN 36 AND 45 THEN '36-45'
        WHEN c.age BETWEEN 46 AND 55 THEN '46-55'
        WHEN c.age BETWEEN 56 AND 65 THEN '56-65'
        ELSE '65+'
    END
ORDER BY age_group;
-- 2. Analyze Income Group
WITH CustomerDemographics AS (
    SELECT
        c.customer_id,
        c.age,
        c.income,
        CASE
            WHEN c.income < 40000 THEN '<40k'
            WHEN c.income BETWEEN 40000 AND 60000 THEN '40k-60k'
            WHEN c.income BETWEEN 60000 AND 80000 THEN '60k-80k'
            WHEN c.income BETWEEN 80000 AND 100000 THEN '80k-100k'
            ELSE '100k+'
        END AS income_group,
        c.gender,
        e.offer_id,
        o.offer_type,
        o.difficulty
    FROM customers c
    INNER JOIN events e ON c.customer_id = e.customer_id
    INNER JOIN offers o ON e.offer_id = o.offer_id
    WHERE e.valid_completion = 'True'
)
-- Income Segmentation
SELECT
    income_group,
    COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN c.customer_id END) AS Total_Sent,
    COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN c.customer_id END) AS Total_Viewed,
    COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN c.customer_id END) AS Total_Completed,
    ROUND(CAST(COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN c.customer_id END) AS FLOAT) / NULLIF(COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN c.customer_id END), 0) * 100, 2) AS [View Rate (%)],
    ROUND(CAST(COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN c.customer_id END) AS FLOAT) / NULLIF(COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN c.customer_id END), 0) * 100, 2) AS [Completion Rate (%)],
    ROUND(CAST(COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN c.customer_id END) AS FLOAT) / NULLIF(COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN c.customer_id END), 0) * 100, 2) AS [Success Rate (%)],
    ROUND(AVG(CAST(e.amount AS FLOAT)), 2) AS [Avg Spend]
FROM CustomerDemographics c
INNER JOIN events e ON c.customer_id = e.customer_id
GROUP BY income_group
ORDER BY income_group;

-- 3. Analyze Gender Group
WITH CustomerDemographics AS (
    SELECT
        c.customer_id,
        c.age,
        c.income,
        CASE
            WHEN c.income < 40000 THEN '<40k'
            WHEN c.income BETWEEN 40000 AND 60000 THEN '40k-60k'
            WHEN c.income BETWEEN 60000 AND 80000 THEN '60k-80k'
            WHEN c.income BETWEEN 80000 AND 100000 THEN '80k-100k'
            ELSE '100k+'
        END AS income_group,
        c.gender,
        e.offer_id,
        o.offer_type,
        o.difficulty
    FROM customers c
    INNER JOIN events e ON c.customer_id = e.customer_id
    INNER JOIN offers o ON e.offer_id = o.offer_id
    WHERE e.valid_completion = 'True'
)
SELECT
    c.gender,
    COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN c.customer_id END) AS Total_Sent,
    COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN c.customer_id END) AS Total_Viewed,
    COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN c.customer_id END) AS Total_Completed,
    ROUND(CAST(COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN c.customer_id END) AS FLOAT) / NULLIF(COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN c.customer_id END), 0) * 100, 2) AS [View Rate (%)],
    ROUND(CAST(COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN c.customer_id END) AS FLOAT) / NULLIF(COUNT(DISTINCT CASE WHEN e.event = 'offer viewed' THEN c.customer_id END), 0) * 100, 2) AS [Completion Rate (%)],
    ROUND(CAST(COUNT(DISTINCT CASE WHEN e.event = 'offer completed' THEN c.customer_id END) AS FLOAT) / NULLIF(COUNT(DISTINCT CASE WHEN e.event = 'offer received' THEN c.customer_id END), 0) * 100, 2) AS [Success Rate (%)],
    ROUND(AVG(CAST(e.amount AS FLOAT)), 2) AS [Avg Spend]
FROM CustomerDemographics c
INNER JOIN events e ON c.customer_id = e.customer_id
GROUP BY c.gender
ORDER BY c.gender;

-- III. Offer-Customer Interaction Analysis
WITH CustomerData AS (
    SELECT
        c.customer_id,
        c.gender,
        c.age,
        c.income,
        e.offer_id,
        o.offer_type
    FROM customers c
    INNER JOIN events e ON c.customer_id = e.customer_id
    INNER JOIN offers o ON e.offer_id = o.offer_id
    WHERE e.valid_completion = 'True'
)
SELECT
    gender,
    CASE
        WHEN age < 25 THEN '18-25'
        WHEN age BETWEEN 26 AND 35 THEN '26-35'
        WHEN age BETWEEN 36 AND 45 THEN '36-45'
        WHEN age BETWEEN 46 AND 55 THEN '46-55'
        WHEN age BETWEEN 56 AND 65 THEN '56-65'
        ELSE '65+'
    END AS age_group,
    CASE
        WHEN income < 40000 THEN '<40k'
        WHEN income BETWEEN 40000 AND 60000 THEN '40k-60k'
        WHEN income BETWEEN 60000 AND 80000 THEN '60k-80k'
        WHEN income BETWEEN 80000 AND 100000 THEN '80k-100k'
        ELSE '100k+'
    END AS income_group,
    offer_type,
    COUNT(CASE WHEN e.event = 'offer received' THEN 1 END) AS total_received,
    COUNT(CASE WHEN e.event = 'offer viewed' THEN 1 END) AS total_viewed,
    COUNT(CASE WHEN e.event = 'offer completed' THEN 1 END) AS total_completed,
    ROUND(CAST(COUNT(CASE WHEN e.event = 'offer viewed' THEN 1 END) AS FLOAT) / NULLIF(COUNT(CASE WHEN e.event = 'offer received' THEN 1 END), 0) * 100, 2) AS view_rate,
    ROUND(CAST(COUNT(CASE WHEN e.event = 'offer completed' THEN 1 END) AS FLOAT) / NULLIF(COUNT(CASE WHEN e.event = 'offer viewed' THEN 1 END), 0) * 100, 2) AS completion_rate
FROM CustomerData c
INNER JOIN events e ON c.customer_id = e.customer_id
GROUP BY
    gender,
    CASE
        WHEN age < 25 THEN '18-25'
        WHEN age BETWEEN 26 AND 35 THEN '26-35'
        WHEN age BETWEEN 36 AND 45 THEN '36-45'
        WHEN age BETWEEN 46 AND 55 THEN '46-55'
        WHEN age BETWEEN 56 AND 65 THEN '56-65'
        ELSE '65+'
    END,
    CASE
        WHEN income < 40000 THEN '<40k'
        WHEN income BETWEEN 40000 AND 60000 THEN '40k-60k'
        WHEN income BETWEEN 60000 AND 80000 THEN '60k-80k'
        WHEN income BETWEEN 80000 AND 100000 THEN '80k-100k'
        ELSE '100k+'
    END,
    offer_type
ORDER BY gender, age_group, income_group, offer_type;