'use strict';
'require view';
'require rpc';

const status = rpc.declare({
	object: 'uz801_cpu',
	method: 'status',
	expect: { '': {} }
});

const apply = rpc.declare({
	object: 'uz801_cpu',
	method: 'apply',
	params: ['cores', 'min_freq', 'max_freq', 'governor'],
	expect: { '': {} }
});

const safe = rpc.declare({
	object: 'uz801_cpu',
	method: 'safe',
	expect: { '': {} }
});

function mhz(v) {
	v = Number(v || 0);
	return v ? (v / 1000000).toFixed(v % 1000000 ? 1 : 0) + ' MHz' : '—';
}

function opt(v, text, selected) {
	return E('option', {
		value: String(v),
		selected: String(v) === String(selected)
	}, text);
}

return view.extend({

	load() {
		return status();
	},

	render(s) {

		const freqs = String(s.available_frequencies || '')
			.trim()
			.split(/\s+/)
			.filter(Boolean);

		const govs = String(s.available_governors || '')
			.trim()
			.split(/\s+/)
			.filter(Boolean);

		const core = E(
			'select',
			{
				id: 'uz801-cores',
				class: 'cbi-input-select'
			},
			[1, 2, 3, 4].map(n =>
				opt(
					n,
					n + (n === 1 ? ' core' : ' cores'),
					Number(s.online_count) === n
				)
			)
		);

		const min = E(
			'select',
			{
				id: 'uz801-min',
				class: 'cbi-input-select'
			},
			freqs.map(f => opt(f, mhz(f), s.min_freq))
		);

		const max = E(
			'select',
			{
				id: 'uz801-max',
				class: 'cbi-input-select'
			},
			freqs.map(f => opt(f, mhz(f), s.max_freq))
		);

		const gov = E(
			'select',
			{
				id: 'uz801-gov',
				class: 'cbi-input-select'
			},
			govs.map(g => opt(g, g, s.governor))
		);

		const msg = E(
			'div',
			{
				id: 'uz801-msg',
				style: 'display:none;margin-bottom:1rem'
			}
		);

		const show = (t, ok) => {
			msg.textContent = t;
			msg.className = 'alert-message ' + (ok ? 'success' : 'warning');
			msg.style.display = '';
		};

		const setRows = data => {

			const table = document.getElementById('uz801-cpus');

			if (!table)
				return;

			table.innerHTML = '';

			for (const c of (data.cpus || [])) {

				table.appendChild(
					E(
						'tr',
						{
							style:
								'background:#b5b5b5;' +
								'border-bottom:6px solid transparent;'
						},
						[
							E(
								'td',
								{
									style:
										'width:150px;' +
										'min-width:150px;' +
										'max-width:150px;' +
										'padding:12px 10px;' +
										'font-weight:500;'
								},
								'CPU' + c.id
							),

							E(
								'td',
								{
									style:
										'width:150px;' +
										'min-width:150px;' +
										'max-width:150px;' +
										'padding:12px 10px;' +
										'font-weight:500;'
								},
								c.online ? 'Online' : 'Offline'
							),

							E(
								'td',
								{
									style:
										'width:150px;' +
										'min-width:150px;' +
										'max-width:150px;' +
										'padding:12px 10px;' +
										'font-weight:500;'
								},
								mhz(c.freq)
							)
						]
					)
				);
			}
		};

		const doApply = async () => {

			const c = Number(
				document.getElementById('uz801-cores').value
			);

			const mn = Number(
				document.getElementById('uz801-min').value
			);

			const mx = Number(
				document.getElementById('uz801-max').value
			);

			const g =
				document.getElementById('uz801-gov').value;

			if (mn > mx)
				return show(
					'Minimum frequency cannot exceed maximum.',
					false
				);

			const r = await apply(c, mn, mx, g);

			setRows(r);

			show(
				'CPU settings applied and saved.',
				true
			);
		};

		const doSafe = async () => {

			if (
				!window.confirm(
					'Restore tested profile: 2 cores, 200 MHz minimum, 800 MHz maximum, schedutil?'
				)
			)
				return;

			const r = await safe();

			setRows(r);

			show(
				'Safe profile restored.',
				true
			);
		};

		return E(
			'div',
			{
				class: 'cbi-map'
			},
			[

				E(
					'h2',
					{},
					_('UZ801 CPU')
				),

				E(
					'div',
					{
						class: 'cbi-map-descr'
					},
					_('Manage online CPU cores, cpufreq limits and governor.')
				),

				msg,

				E(
					'fieldset',
					{
						class: 'cbi-section'
					},
					[

						E(
							'legend',
							{},
							_('CPU configuration')
						),

						E(
							'div',
							{
								class: 'cbi-value'
							},
							[
								E(
									'label',
									{
										class: 'cbi-value-title',
										for: 'uz801-cores'
									},
									_('Online cores')
								),

								E(
									'div',
									{
										class: 'cbi-value-field'
									},
									[core]
								)
							]
						),

						E(
							'div',
							{
								class: 'cbi-value'
							},
							[
								E(
									'label',
									{
										class: 'cbi-value-title',
										for: 'uz801-min'
									},
									_('Minimum frequency')
								),

								E(
									'div',
									{
										class: 'cbi-value-field'
									},
									[min]
								)
							]
						),

						E(
							'div',
							{
								class: 'cbi-value'
							},
							[
								E(
									'label',
									{
										class: 'cbi-value-title',
										for: 'uz801-max'
									},
									_('Maximum frequency')
								),

								E(
									'div',
									{
										class: 'cbi-value-field'
									},
									[max]
								)
							]
						),

						E(
							'div',
							{
								class: 'cbi-value'
							},
							[
								E(
									'label',
									{
										class: 'cbi-value-title',
										for: 'uz801-gov'
									},
									_('Governor')
								),

								E(
									'div',
									{
										class: 'cbi-value-field'
									},
									[gov]
								)
							]
						)
					]
				),

				E(
					'fieldset',
					{
						class: 'cbi-section'
					},
					[

						E(
							'legend',
							{},
							_('Current status')
						),

						/* Current status summary table */

						E(
							'table',
							{
								class: 'table',
								style:
									'width:100%;' +
									'table-layout:fixed;' +
									'margin-bottom:20px;'
							},
							[
								E(
									'tbody',
									{},
									[

										E(
											'tr',
											{
												style:
												'background:#555;' +
												'color:#fff;'

											},
											[
												E(
													'td',
													{
														style:
															'width:150px;' +
															'font-weight:bold;' +
															'padding:10px;'
													},
													_('Online CPUs')
												),

												E(
													'td',
													{
														style:
															'width:150px;' +
															'padding:10px;'
													},
													s.online
												)
											]
										),

										E(
											'tr',
											{},
											[
												E(
													'td',
													{
														style:
															'width:150px;' +
															'font-weight:bold;' +
															'padding:10px;'
													},
													_('Driver')
												),

												E(
													'td',
													{
														style:
															'width:150px;' +
															'padding:10px;'
													},
													s.driver
												)
											]
										),

										E(
											'tr',
											{
												style:
												'background:#555;' +
												'color:#fff;'
											},
											[
												E(
													'td',
													{
														style:
															'width:150px;' +
															'font-weight:bold;' +
															'padding:10px;'
													},
													_('Minimum')
												),

												E(
													'td',
													{
														style:
															'width:150px;' +
															'padding:10px;'
													},
													mhz(s.min_freq)
												)
											]
										),

										E(
											'tr',
											{},
											[
												E(
													'td',
													{
														style:
															'width:150px;' +
															'font-weight:bold;' +
															'padding:10px;'
													},
													_('Maximum')
												),

												E(
													'td',
													{
														style:
															'width:150px;' +
															'padding:10px;'
													},
													mhz(s.max_freq)
												)
											]
										),

										E(
											'tr',
											{
												style:
												'background:#555;' +
												'color:#fff;'
											},
											[
												E(
													'td',
													{
														style:
															'width:150px;' +
															'font-weight:bold;' +
															'padding:10px;'
													},
													_('Governor')
												),

												E(
													'td',
													{
														style:
															'width:150px;' +
															'padding:10px;'
													},
													s.governor
												)
											]
										)
									]
								)
							]
						),

						/* CPU cores table */

						E(
							'table',
							{
								class: 'table',
								style:
									'width:100%;' +
									'table-layout:fixed;' +
									'border-collapse:separate;' +
									'border-spacing:0 6px;'
							},
							[

								E(
									'thead',
									{},
									[
										E(
											'tr',
											{
												style:
													'background:#555;' +
													'color:#fff;'
											},
											[

												E(
													'th',
													{
														style:
															'width:150px;' +
															'min-width:150px;' +
															'max-width:150px;' +
															'height:50px;' +
															'padding:12px 10px;' +
															'font-weight:bold;' +
															'text-align:left;'
													},
													_('CPU')
												),

												E(
													'th',
													{
														style:
															'width:150px;' +
															'min-width:150px;' +
															'max-width:150px;' +
															'height:50px;' +
															'padding:12px 10px;' +
															'font-weight:bold;' +
															'text-align:left;'
													},
													_('State')
												),

												E(
													'th',
													{
														style:
															'width:150px;' +
															'min-width:150px;' +
															'max-width:150px;' +
															'height:50px;' +
															'padding:12px 10px;' +
															'font-weight:bold;' +
															'text-align:left;'
													},
													_('Current frequency')
												)
											]
										)
									]
								),

								E(
									'tbody',
									{
										id: 'uz801-cpus'
									},
									(s.cpus || []).map(c =>
										E(
											'tr',
											{
												style:
													'background:#b5b5b5;' +
													'border-bottom:6px solid transparent;'
											},
											[

												E(
													'td',
													{
														style:
															'width:150px;' +
															'min-width:150px;' +
															'max-width:150px;' +
															'padding:12px 10px;' +
															'font-weight:500;'+
															'color:blue;'
													},
													'CPU' + c.id
												),

												E(
													'td',
													{
														style:
															'width:150px;' +
															'min-width:150px;' +
															'max-width:150px;' +
															'padding:12px 10px;' +
															'font-weight:500;'+
															'color:brown;'
													},
													c.online ? 'Online' : 'Offline'
												),

												E(
													'td',
													{
														style:
															'width:150px;' +
															'min-width:150px;' +
															'max-width:150px;' +
															'padding:12px 10px;' +
															'font-weight:500;'+
															'color:blue;'
													},
													mhz(c.freq)
												)
											]
										)
									)
								)
							]
						)
					]
				),

				E(
					'div',
					{
						class: 'cbi-page-actions'
					},
					[
						E(
							'button',
							{
								class: 'btn cbi-button cbi-button-apply',
								click: doApply
							},
							_('Apply')
						),

						' ',

						E(
							'button',
							{
								class: 'btn cbi-button cbi-button-reset',
								click: doSafe
							},
							_('Restore Safe Profile')
						)
					]
				)
			]
		);
	}
});