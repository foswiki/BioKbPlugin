
var fieldcounter = 1;
var fieldlimit = 10;

function addInput(divName, template) {
    if (fieldcounter == fieldlimit) {
        alert("You have reached the limit of adding " + counter + " inputs");
    } else {
        var newdiv = document.createElement("div");
        newdiv.innerHTML = document.getElementById(template).innerHTML;
        document.getElementById(divName).appendChild(newdiv);
        fieldcounter++;
    }
}



