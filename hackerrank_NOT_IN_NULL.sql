/*
You are given a table, BST, containing two columns: N and P, where N represents the value of a node in Binary Tree, and P is the parent of N.

n Integer
p Integer

Write a query to find the node type of Binary Tree ordered by the value of the node. Output one of the following for each node:

Root: If node is root node.
Leaf: If node is leaf node.
Inner: If node is neither root nor leaf node.
Sample Input

1 2  
2 4  
3 2  
4 15  
5 6  
6 4  
7 6  
8 9  
9 11  
10 9  
11 15  
12 13  
13 11  
14 13  
15 NULL  


Sample Output

1 Leaf
2 Inner
3 Leaf
5 Root
6 Leaf
8 Inner
9 Leaf

*/

--root is WHERE BST.p is NULL
--inner is WHERE BST.p is NOT NULL and BST.n IN (SELECT DISTINCT P FROM BST)
--leaf is WHERE BST.n NOT IN (SELECT DISTINCT P FROM BST)
--SELECT * FROM BST ORDER BY n;
SELECT n
, CASE 
WHEN p IS NULL THEN 'Root'
WHEN p is NOT NULL and n NOT IN (SELECT DISTINCT nvl(P,0) FROM BST) THEN 'Leaf'
ELSE 'Inner' END
FROM BST ORDER BY n;

/*
1 2 leaf 
2 4 inner 
3 2 leaf 
4 15 inner 
5 6 leaf 
6 4 inner 
7 6 leaf 
8 9 leaf 
9 11 inner 
10 9 leaf 
11 15 inner 
12 13 leaf 
13 11 inner 
14 13 leaf 
15 NULL root 

if there is at least one row with a null value for tid in table3 you will get no rows returned. This is because to Oracle null is like saying "I don't know what this value is". Oracle can't say with certainty that the value you are searching for is definitely not in your sub-select because it doesn't know what this "not-known" value actually is. Also, the documentation says it works that way: http://docs.oracle.com/cd/B28359_01/server.111/b28286/conditions013.htm
*/
