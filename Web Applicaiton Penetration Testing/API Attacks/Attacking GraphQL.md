enumerating GraphQL
![[Pasted image 20261005115804.png]]


## Introspection

[Introspection](https://graphql.org/learn/introspection/) is a GraphQL feature that enables users to query the GraphQL API about the structure of the backend system. As such, users can use introspection queries to obtain all queries supported by the API schema. These introspection queries query the `__schema` field.


For instance, we can identify all GraphQL types supported by the backend using the following query


```
{
  __schema {
    types {
      name
    }
  }
}
```

The results contain basic default types, such as `Int` or `Boolean`, but also all custom types, such as `UserObject`

![[Pasted image 20261005120615.png]]


Now that we know a type, we can follow up and obtain the name of all of the type's fields with the following introspection query:


```
{
  __type(name: "UserObject") {
    name
    fields {
      name
      type {
        name
        kind
      }
    }
  }
}
```


In the result, we can see details we would expect from a user object, such as `username` and `password`, as well as their data types

![[Pasted image 20261005120637.png]]


Furthermore, we can obtain all the queries supported by the backend using this query:


```
{
  __schema {
    queryType {
      fields {
        name
        description
      }
    }
  }
}
```


Knowing all supported queries helps us identify potential attack vectors that we can use to obtain sensitive information. Lastly, we can use the following "general" introspection query that dumps all information about types, fields, and queries supported by the backend:

```
query IntrospectionQuery {
      __schema {
        queryType { name }
        mutationType { name }
        subscriptionType { name }
        types {
          ...FullType
        }
        directives {
          name
          description
          
          locations
          args {
            ...InputValue
          }
        }
      }
    }

    fragment FullType on __Type {
      kind
      name
      description
      
      fields(includeDeprecated: true) {
        name
        description
        args {
          ...InputValue
        }
        type {
          ...TypeRef
        }
        isDeprecated
        deprecationReason
      }
      inputFields {
        ...InputValue
      }
      interfaces {
        ...TypeRef
      }
      enumValues(includeDeprecated: true) {
        name
        description
        isDeprecated
        deprecationReason
      }
      possibleTypes {
        ...TypeRef
      }
    }

    fragment InputValue on __InputValue {
      name
      description
      type { ...TypeRef }
      defaultValue
    }

    fragment TypeRef on __Type {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
                ofType {
                  kind
                  name
                  ofType {
                    kind
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
```


The result of this query is quite large and complex. However, we can visualize the schema using the tool [GraphQL-Voyager](https://github.com/graphql-kit/graphql-voyager). For this module, we will use the [GraphQL Demo](https://graphql-kit.com/graphql-voyager/). However, in a real engagement, we should follow the GitHub instructions to host the tool ourselves, ensuring that no sensitive information leaves our system.

In the demo, we can click `CHANGE SCHEMA` and select `INTROSPECTION`. After pasting the result of the above introspection query in the text field and clicking on `DISPLAY`, the backend's GraphQL schema is visualized for us. We can explore all supported queries, types, and fields:


![[Pasted image 20261005121704.png]]


![[Pasted image 20261005121713.png]]



# Insecure Direct Object Reference (IDOR)


Like REST APIs, broken authorization, particularly Insecure Direct Object Reference (IDOR) vulnerabilities, are common security issues in GraphQL. To learn more about IDOR vulnerabilities

## Identifying IDOR


To identify issues related to broken authorization, we first need to identify potential attack points that would enable us to access data we are not authorized to access. Enumerating the web application, we can observe that the following GraphQL query is sent when we access our user profile


![[Pasted image 20261005171322.png]]


## Exploiting IDOR


To demonstrate the impact of this IDOR vulnerability, we need to identify the data that can be accessed without authorization. To do so, we are going to use the following introspection queries to determine all fields of the `User` type


```
{
  __type(name: "UserObject") {
    name
    fields {
      name
      type {
        name
        kind
      }
    }
  }
}
```


![[Pasted image 20261005171454.png]]


Let us adjust the initial GraphQL query to check if we can exploit the IDOR vulnerability to obtain another user's password by adding the `password` field in the GraphQL query



```
{
  user(username: "test") {
    username
    password
  }
}
```


From the result, we can see that we have successfully obtained the user's password:

![[Pasted image 20261005171539.png]]


# Injection Attacks


One of the most common web vulnerabilities are injection attacks such as [SQL Injection](https://academy.hackthebox.com/module/details/33), [Cross-Site Scripting (XSS)](https://academy.hackthebox.com/module/details/103), and [Command Injection](https://academy.hackthebox.com/module/details/109). Like all web applications, GraphQL implementations can also be vulnerable to these issues.


## SQL Injection


To identify if a query requires an argument, we can send the query without any arguments and analyze the response. If the backend expects an argument, the response contains an error that tells us the name of the required argument. For instance, the following error message tells us that the `postByAuthor` query requires the `author` argument:


![[Pasted image 20261005172655.png]]

After supplying the `author` argument, the query is executed successfully:


![[Pasted image 20261005172702.png]]


Let us move on to the `user` query. If we try the same payload there, the query still returns the previous result, indicating a SQL injection vulnerability


![[Pasted image 20261005172820.png]]


If we simply inject a single quote, the response contains a SQL error, confirming the vulnerability


![[Pasted image 20261005172843.png]]



Since the SQL query is displayed in the SQL error, we can construct a UNION-based SQL injection query to exfiltrate data from the SQL database. Remember that the database may contain data that cannot be queried through the GraphQL API. As such, we should check for any sensitive data in the database that we can access.


To construct a UNION-based SQL injection payload, let us take another look at the results of the introspection query:


![[Pasted image 20261005173235.png]]



The vulnerable `user` query returns a `UserObject`, so let us focus on that object. As we can see, the object consists of six fields and a link (`posts`). The fields correspond to columns in the database table. As such, our UNION-based SQL injection payload needs to contain six columns to match the number of columns in the original query. Furthermore, the fields we specify in our GraphQL query correspond to the columns returned in the response. For instance, since the `username` is a `UserObject's` third field, querying for the `username` will result in the third column of our UNION-based payload being reflected in the response.

As the GraphQL query only returns the first row, we will use the [GROUP_CONCAT](https://mariadb.com/kb/en/group_concat/) function to exfiltrate multiple rows at a time. This enables us to exfiltrate all table names in the current database with the following payload:



```
{
  user(username: "x' UNION SELECT 1,2,GROUP_CONCAT(table_name),4,5,6 FROM information_schema.tables WHERE table_schema=database()-- -") {
    username
  }
}
```


The response contains all table names concatenated in the `username` field:


```
{
  "data": {
    "user": {
      "username": "user,secret,post"
    }
  }
}
```


Since this is a SQL injection vulnerability, similar to any other web application, we can utilize all SQL payloads and attack vectors to enumerate column names and ultimately exfiltrate data. For more details on exploiting SQL injections, check out the [SQL Injection Fundamentals](https://academy.hackthebox.com/module/details/33) and [Advanced SQL Injections](https://academy.hackthebox.com/module/details/188) modules.



## Cross-Site Scripting (XSS)


XSS vulnerabilities can occur if GraphQL responses are inserted into the HTML page without proper sanitization. Similar to the above SQL injection vulnerability, we should investigate any GraphQL arguments for potential XSS injection points. However, in this case, neither queries return an XSS payload:

![[Pasted image 20261005173348.png]]


XSS vulnerabilities can also occur if invalid arguments are reflected in error messages. Let us examine the `post` query, which requires an integer ID as an argument. If we instead submit a string argument containing an XSS payload, we can see that the XSS payload is reflected without proper encoding in the GraphQL error message

![[Pasted image 20261005173428.png]]


However, if we attempt to trigger the URL from the corresponding GET parameter by accessing the URL `/post?id=<script>alert(1)</script>`, we can observe that the page simply breaks, and the XSS payload is not triggered.

