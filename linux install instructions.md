
Shahmir Khan June 29, 2025

To install on linux first do:
```
python3 -m venv venv
source venv/bin/activate
pip install requests
```

When I was setting up the repo I got

"A submodule points to a commit which does not exist" error


To fix this error I first forked the repo on github
Using the github website I commented out everything from the .gitmodules file in my fork
I then cloned my fork to my computer, it cloned without errors this time.
Now we have to add the modules back.


First lets clean up all old directories and references to the previous submodules:
```
git rm --cached extensions/godot-cpp
rm -rf extensions/godot-cpp
rm -rf .git/modules/extensions/godot-cpp
```

now re-add the godot-cpp module:
```
git submodule add -b 4.3 https://github.com/godotengine/godot-cpp extensions/godot-cpp
```

remove old submodule references for default_assets
```
git rm --cached default_assets
rm -rf default_assets
rm -rf .git/modules/default_assets
```

now re-add the default_assets module:
```
git submodule add https://github.com/OpenChamp/default_assets default_assets
```


This still didn't work 

```
git rm --cached default_assets
rm -rf default_assets
rm -rf .git/modules/default_assets
```

```
git submodule add https://github.com/OpenChamp/default_assets default_assets
```

```
git add .gitmodules default_assets
git commit -m "Fix broken default_assets submodule reference"
```

```
git submodule update --init --recursive
```