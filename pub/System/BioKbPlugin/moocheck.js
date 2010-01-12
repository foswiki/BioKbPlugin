/*
* FancyForm 0.94
* By Vacuous Virtuoso, lipidity.com
* ---
* Checkbox and radio input replacement script.
* Toggles defined class when input is selected.
*/

var FancyForm = {
	start: function(elements, options){
		FancyForm.initing = 1;
		if($type(elements)!='array') elements = $$('input');
		if(!options) options = [];
		FancyForm.onclasses = ($type(options['onClasses']) == 'object') ? options['onClasses'] : {
			checkbox: 'checked',
			radio: 'selected'
		}
		FancyForm.offclasses = ($type(options['offClasses']) == 'object') ? options['offClasses'] : {
			checkbox: 'unchecked',
			radio: 'unselected'
		}
		if($type(options['extraClasses']) == 'object'){
			FancyForm.extra = options['extraClasses'];
		} else if(options['extraClasses']){
			FancyForm.extra = {
				checkbox: 'f_checkbox',
				radio: 'f_radio',
				on: 'f_on',
				off: 'f_off',
				all: 'fancy'
			}
		} else {
			FancyForm.extra = {};
		}
		FancyForm.onSelect = $pick(options['onSelect'], function(el){});
		FancyForm.onDeselect = $pick(options['onDeselect'], function(el){});
		var keeps = [];
		FancyForm.chks = elements.filter(function(chk){
			if( $type(chk) != 'element' ) return false;
			if( chk.getTag() == 'input' && (FancyForm.onclasses[chk.getProperty('type')]) ){
				var el = chk.getParent();
				if(el.getElement('input')==chk){
					el.type = chk.getProperty('type');
					el.inputElement = chk;
					this.push(el);
				} else {
					chk.addEvent('click',function(ev){
				if(e.event.stopPropagation)
					e.event.stopPropagation();
});
				}
			} else if( (chk.inputElement = chk.getElement('input')) && (FancyForm.onclasses[(chk.type = chk.inputElement.getProperty('type'))]) ){
				return true;
			}
			return false;
		}.bind(keeps));
		FancyForm.chks = FancyForm.chks.merge(keeps);
		keeps = null;
		FancyForm.chks.each(function(chk){
			var c = chk.inputElement;
			c.setStyle('position', 'absolute');
			c.setStyle('left', '-9999px');
			chk.addEvent('selectStart', function(e){new Event(e).stop()});
			chk.name = c.getProperty('name');
			FancyForm.update(chk);
			chk.addEvent('click', function(f){
				if(!FancyForm.initing && $type(chk.inputElement.onclick) == 'function')
					 chk.inputElement.onclick();
				var e = new Event(f);
				e.stop(); e.type = 'prop';
				chk.inputElement.fireEvent('click', e, 1);
			});
			chk.addEvent('mousedown', function(e){
				if($type(chk.inputElement.onmousedown) == 'function')
					chk.inputElement.onmousedown();
				new Event(e).preventDefault();
			});
			chk.addEvent('mouseup', function(e){
				if($type(chk.inputElement.onmouseup) == 'function')
					chk.inputElement.onmouseup();
			});
			chk.inputElement.addEvent('focus', function(e){
				if(FancyForm.focus)
					chk.setStyle('outline', '1px dotted');
			});
			chk.inputElement.addEvent('blur', function(e){
				chk.setStyle('outline', 0);
			});
			chk.inputElement.addEvent('click', function(e){
				if(e.event.stopPropagation)
					e.event.stopPropagation();
				if(c.getProperty('disabled')) // c.getStyle('position') != 'absolute'
					return;
				if (!chk.hasClass(FancyForm.onclasses[chk.type]))
					c.setProperty('checked', 'checked');
				else if(chk.type != 'radio')
					c.setProperty('checked', false);
				if(e.type == 'prop')
					FancyForm.focus = 0;
				FancyForm.update(chk);
				FancyForm.focus = 1;
			});
			chk.inputElement.addEvent('mouseup', function(e){
				if(e.event.stopPropagation)
					e.event.stopPropagation();
			});
			chk.inputElement.addEvent('mousedown', function(e){
				if(e.event.stopPropagation)
					e.event.stopPropagation();
			});
			if(extraclass = FancyForm.extra[chk.type])
				chk.addClass(extraclass);
			if(extraclass = FancyForm.extra['all'])
				chk.addClass(extraclass);
		});
		FancyForm.initing = 0;
		$each($$('form'), function(x) {
			x.addEvent('reset', function(a) {
				window.setTimeout(function(){FancyForm.chks.each(function(x){FancyForm.update(x);x.inputElement.blur()})}, 200);
			});
		});
	},
	update: function(chk){
		if(!chk.inputElement.getProperty('checked')) {
			chk.removeClass(FancyForm.onclasses[chk.type]);
			chk.addClass(FancyForm.offclasses[chk.type]);
			if(extraclass = FancyForm.extra['off'])
				chk.addClass(extraclass);
			if(extraclass = FancyForm.extra['on'])
				chk.removeClass(extraclass);
			if(!FancyForm.initing)
				FancyForm.onDeselect(chk);
		} else {
			chk.removeClass(FancyForm.offclasses[chk.type]);
			chk.addClass(FancyForm.onclasses[chk.type]);
			if (chk.type == 'radio'){
				FancyForm.chks.each(function(other){
					if (other.name == chk.name && other != chk) {
						other.inputElement.setProperty('checked', false);
						FancyForm.update(other);
					}
				});
			}
			if(extraclass = FancyForm.extra['on'])
				chk.addClass(extraclass);
			if(extraclass = FancyForm.extra['off'])
				chk.removeClass(extraclass);
			if(!FancyForm.initing)
				FancyForm.onSelect(chk);
		}
		if(!FancyForm.initing)
			chk.inputElement.focus();
	},
	all: function(){
		FancyForm.chks.each(function(chk){
			chk.inputElement.setProperty('checked', 'checked');
			FancyForm.update(chk);
		});
	},
	none: function(){
		FancyForm.chks.each(function(chk){
			chk.inputElement.setProperty('checked', false);
			FancyForm.update(chk);
		});
	}
};

window.addEvent('domready', function(){
	FancyForm.start( $$('.fancy-box') );	
});
