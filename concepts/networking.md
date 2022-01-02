[```clientSide/ServerConnection```](../src/cubyz/clientSide/ServerConnection.java) is the clientSide part of the networking code\
[```server/User```](../src/cubyz/server/User.java) Is the serverSide part of the networking code.\
[```server/UserManager```](../src/cubyz/server/User.java) Contains all of the users.\
[```server/Server```](../src/cubyz/server/Server.java) Mainfile for the server.\

#Messages
Messages are send via JSON objects: 
```json.writeObjectToStream(out)```
and received via:
```JsonParser.parseObjectFromStream(in)``` \
\
The attribute **"type"** of the JSON Object indicates how it should be interpreted:

|type|interpretation|attachment|
|---|---|---|
|clientInformation|initial message, contains clientinformations|
|worldAssets|world specific assets|binary zip file|