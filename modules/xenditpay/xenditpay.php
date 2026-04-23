<?php
if (!defined('_PS_VERSION_')) {
    exit;
}

use PrestaShop\PrestaShop\Core\Payment\PaymentOption;

class XenditPay extends PaymentModule
{
    public function __construct()
    {
        $this->name = 'xenditpay';
        $this->tab = 'payments_gateways';
        $this->version = '1.0.0';
        $this->author = 'Antigravity';
        $this->need_instance = 0;
        $this->ps_versions_compliancy = [
            'min' => '1.7.0.0',
            'max' => _PS_VERSION_
        ];
        $this->bootstrap = true;

        parent::__construct();

        $this->displayName = $this->l('Xendit Payment');
        $this->description = $this->l('Accept payments via Xendit gateway.');

        $this->confirmUninstall = $this->l('Are you sure you want to uninstall?');
    }

    public function install()
    {
        if (!parent::install() ||
            !$this->registerHook('paymentOptions') ||
            !$this->registerHook('paymentReturn')
        ) {
            return false;
        }

        // Add a new order state for Awaiting Xendit Payment if it doesn't exist
        $this->createOrderState();

        return true;
    }

    public function uninstall()
    {
        if (!parent::uninstall() ||
            !Configuration::deleteByName('XENDIT_PUBLIC_KEY') ||
            !Configuration::deleteByName('XENDIT_SECRET_KEY') ||
            !Configuration::deleteByName('XENDIT_WEBHOOK_TOKEN') ||
            !Configuration::deleteByName('XENDIT_OS_AWAITING')
        ) {
            return false;
        }
        return true;
    }

    private function createOrderState()
    {
        if (!Configuration::get('XENDIT_OS_AWAITING')) {
            $orderState = new OrderState();
            $orderState->name = array();
            foreach (Language::getLanguages() as $language) {
                $orderState->name[$language['id_lang']] = 'Awaiting Xendit Payment';
            }
            $orderState->send_email = false;
            $orderState->color = '#4169E1';
            $orderState->hidden = false;
            $orderState->delivery = false;
            $orderState->logable = false;
            $orderState->invoice = false;
            $orderState->add();

            Configuration::updateValue('XENDIT_OS_AWAITING', (int)$orderState->id);
        }
    }

    public function getContent()
    {
        $output = '';

        if (Tools::isSubmit('submitXenditpayModule')) {
            $publicKey = (string)Tools::getValue('XENDIT_PUBLIC_KEY');
            $secretKey = (string)Tools::getValue('XENDIT_SECRET_KEY');
            $webhookToken = (string)Tools::getValue('XENDIT_WEBHOOK_TOKEN');

            Configuration::updateValue('XENDIT_PUBLIC_KEY', $publicKey);
            Configuration::updateValue('XENDIT_SECRET_KEY', $secretKey);
            Configuration::updateValue('XENDIT_WEBHOOK_TOKEN', $webhookToken);

            $output .= $this->displayConfirmation($this->l('Settings updated'));
        }

        return $output . $this->renderForm();
    }

    protected function renderForm()
    {
        $helper = new HelperForm();

        $helper->show_toolbar = false;
        $helper->table = $this->table;
        $helper->module = $this;
        $helper->default_form_language = $this->context->language->id;
        $helper->allow_employee_form_lang = Configuration::get('PS_BO_ALLOW_EMPLOYEE_FORM_LANG', 0);

        $helper->identifier = $this->identifier;
        $helper->submit_action = 'submitXenditpayModule';
        $helper->currentIndex = $this->context->link->getAdminLink('AdminModules', false)
            .'&configure='.$this->name.'&tab_module='.$this->tab.'&module_name='.$this->name;
        $helper->token = Tools::getAdminTokenLite('AdminModules');

        $helper->tpl_vars = array(
            'fields_value' => $this->getConfigFormValues(),
            'languages' => $this->context->controller->getLanguages(),
            'id_language' => $this->context->language->id,
        );

        return $helper->generateForm(array($this->getConfigForm()));
    }

    protected function getConfigForm()
    {
        return array(
            'form' => array(
                'legend' => array(
                    'title' => $this->l('Xendit Settings'),
                    'icon' => 'icon-cogs',
                ),
                'input' => array(
                    array(
                        'type' => 'text',
                        'label' => $this->l('Public Key'),
                        'name' => 'XENDIT_PUBLIC_KEY',
                        'size' => 50,
                        'required' => true,
                    ),
                    array(
                        'type' => 'text',
                        'label' => $this->l('Secret Key'),
                        'name' => 'XENDIT_SECRET_KEY',
                        'size' => 50,
                        'required' => true,
                    ),
                    array(
                        'type' => 'text',
                        'label' => $this->l('Webhook Verification Token'),
                        'name' => 'XENDIT_WEBHOOK_TOKEN',
                        'size' => 50,
                        'desc' => $this->l('Found in your Xendit Dashboard Settings -> Webhooks.'),
                        'required' => false,
                    ),
                ),
                'submit' => array(
                    'title' => $this->l('Save'),
                ),
            ),
        );
    }

    protected function getConfigFormValues()
    {
        return array(
            'XENDIT_PUBLIC_KEY' => Configuration::get('XENDIT_PUBLIC_KEY', 'xnd_public_production_J35t1LlVY2E6wh5GMcNzcz5IgTNbbnGXKPsYj6WZuBvvNwDQVmzElgBMwHx4FZ'),
            'XENDIT_SECRET_KEY' => Configuration::get('XENDIT_SECRET_KEY', 'xnd_production_rPzstHG2lk2oYoTBexUL0uwvj6vMTkhKNaMWtBPHEINQiGRacZN4gsYZCmsoQA'),
            'XENDIT_WEBHOOK_TOKEN' => Configuration::get('XENDIT_WEBHOOK_TOKEN', ''),
        );
    }

    public function hookPaymentOptions($params)
    {
        if (!$this->active) {
            return;
        }

        $paymentOption = new PaymentOption();
        $paymentOption->setCallToActionText($this->l('Pay with Xendit'))
                      ->setAction($this->context->link->getModuleLink($this->name, 'redirect', array(), true))
                      ->setAdditionalInformation($this->l('You will be redirected to Xendit to securely complete your payment.'));

        return [$paymentOption];
    }

    public function hookPaymentReturn($params)
    {
        if (!$this->active) {
            return;
        }
        $this->smarty->assign(array(
            'shop_name' => $this->context->shop->name,
            'contact_url' => $this->context->link->getPageLink('contact', true)
        ));
        return $this->display(__FILE__, 'views/templates/hook/payment_return.tpl');
    }
}
